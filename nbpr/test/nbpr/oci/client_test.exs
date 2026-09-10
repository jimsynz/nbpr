defmodule NBPR.OCI.ClientTest do
  use ExUnit.Case, async: false

  alias NBPR.OCI.Client
  alias NBPR.Artifact.Resolvers.OCI

  setup do
    original = Application.fetch_env(:nbpr, :registry)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:nbpr, :registry, value)
        :error -> Application.delete_env(:nbpr, :registry)
      end
    end)

    for key <- ["NBPR_REGISTRY_USERNAME", "NBPR_REGISTRY_TOKEN"] do
      value = System.get_env(key)
      System.delete_env(key)

      on_exit(fn ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end

    :ok
  end

  test "parses Forgejo namespaces, nested images and explicit development HTTP" do
    assert Client.parse_prefix!("forgejo.example.com/org/firmware") ==
             {"https://forgejo.example.com", "org/firmware"}

    assert Client.parse_prefix!("http://localhost:3000/org") == {"http://localhost:3000", "org"}

    for bad <- [
          "https://user:password@host/org",
          "host",
          "host/org/",
          "host/org?x=1",
          "ftp://host/org"
        ] do
      assert_raise ArgumentError, fn -> Client.parse_prefix!(bad) end
    end
  end

  test "does not reuse project credentials for upstream registries" do
    Application.put_env(:nbpr, :registry, "forgejo.example.com/org")
    System.put_env("NBPR_REGISTRY_USERNAME", "builder")
    System.put_env("NBPR_REGISTRY_TOKEN", "test-token")

    assert Client.new("forgejo.example.com/org", "nbpr_jq").credentials ==
             {"builder", "test-token"}

    assert Client.new("other.example.com/org", "nbpr_jq").credentials == nil
  end

  test "answers Forgejo Bearer challenges using the advertised realm and push scope" do
    {base, task} =
      server(3, fn index, method, path, headers, base ->
        case index do
          0 ->
            assert method == "GET"
            refute headers["authorization"]

            {401,
             [
               {"www-authenticate",
                ~s(Bearer realm="#{base}/v2/token",service="container_registry",scope="repository:org/nbpr_jq:pull")}
             ], ""}

          1 ->
            uri = URI.parse(path)
            assert uri.path == "/v2/token"

            assert URI.decode_query(uri.query) == %{
                     "service" => "container_registry",
                     "scope" => "repository:org/nbpr_jq:push,pull"
                   }

            assert headers["authorization"] == "Basic " <> Base.encode64("builder:test-token")
            {200, [], ~s({"access_token":"test-bearer"})}

          2 ->
            assert path == "/v2/org/nbpr_jq/manifests/test"
            assert headers["authorization"] == "Bearer test-bearer"
            {200, [], "manifest"}
        end
      end)

    prefix = base <> "/org"
    Application.put_env(:nbpr, :registry, prefix)
    System.put_env("NBPR_REGISTRY_USERNAME", "builder")
    System.put_env("NBPR_REGISTRY_TOKEN", "test-token")
    client = Client.new(prefix, "nbpr_jq", "push,pull")

    assert {:ok, 200, _, "manifest"} =
             Client.request(client, :get, "/v2/org/nbpr_jq/manifests/test")

    Task.await(task)
  end

  test "supports Basic authentication" do
    {base, task} =
      server(2, fn index, _, _, headers, _ ->
        if index == 0 do
          {401, [{"www-authenticate", ~s(Basic realm="registry")}], ""}
        else
          assert headers["authorization"] == "Basic " <> Base.encode64("builder:test-token")
          {200, [], "ok"}
        end
      end)

    client = %{Client.new(base <> "/org", "nbpr_jq") | credentials: {"builder", "test-token"}}
    assert {:ok, 200, _, "ok"} = Client.request(client, :get, "/v2/")
    Task.await(task)
  end

  test "refuses to send registry credentials to another token origin" do
    {base, task} =
      server(1, fn _, _, _, _, _ ->
        {401, [{"www-authenticate", ~s(Bearer realm="https://other.example/token")}], ""}
      end)

    client = %{Client.new(base <> "/org", "nbpr_jq") | credentials: {"builder", "test-token"}}
    assert {:error, :untrusted_registry_auth_realm} = Client.request(client, :get, "/v2/")

    assert {:error, :cross_origin_registry_request} =
             Client.request(client, :put, "https://other.example/upload")

    Task.await(task)
  end

  test "returns a miss for a missing manifest" do
    {base, task} =
      server(1, fn _, method, _, _, _ ->
        assert method == "HEAD"
        {404, [], ""}
      end)

    assert OCI.tag_exists?(%{prefix: base <> "/org", package: "nbpr_jq", tag: "missing"}) ==
             {:ok, false}

    Task.await(task)
  end

  test "rejects corrupt tarballs before writing the download" do
    digest = String.duplicate("0", 64)

    {base, task} =
      server(2, fn index, _, _, _, _ ->
        if index == 0 do
          {200, [],
           ~s({"layers":[{"mediaType":"application/vnd.nbpr.tarball.v1+tar+gzip","digest":"sha256:#{digest}"}]})}
        else
          {200, [], "corrupt bytes"}
        end
      end)

    dest = Path.join(System.tmp_dir!(), "nbpr-corrupt-#{System.unique_integer([:positive])}")

    assert OCI.get(%{prefix: base <> "/org", package: "nbpr_jq", tag: "test"}, dest) ==
             {:error, :blob_digest_mismatch}

    refute File.exists?(dest)
    Task.await(task)
  end

  # A loopback HTTP fixture exercises the actual :httpc transport. Connections
  # close after each response, so the expected sequence is deterministic.
  defp server(count, handler) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    base = "http://127.0.0.1:#{port}"
    on_exit(fn -> :gen_tcp.close(listener) end)

    task =
      Task.async(fn ->
        for index <- 0..(count - 1) do
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          request = read_headers(socket, "")
          [first | lines] = String.split(request, "\r\n", trim: true)
          [method, path, _] = String.split(first, " ")

          headers =
            Map.new(lines, fn line ->
              [key, value] = String.split(line, ":", parts: 2)
              {String.downcase(key), String.trim(value)}
            end)

          {status, response_headers, body} = handler.(index, method, path, headers, base)

          response_headers = [
            {"content-length", byte_size(body)},
            {"connection", "close"} | response_headers
          ]

          response = [
            "HTTP/1.1 #{status} Response\r\n",
            Enum.map(response_headers, fn {k, v} -> "#{k}: #{v}\r\n" end),
            "\r\n",
            body
          ]

          :ok = :gen_tcp.send(socket, response)
          :gen_tcp.close(socket)
        end

        :gen_tcp.close(listener)
      end)

    {base, task}
  end

  defp read_headers(socket, acc) do
    if String.contains?(acc, "\r\n\r\n") do
      acc |> String.split("\r\n\r\n", parts: 2) |> hd()
    else
      {:ok, data} = :gen_tcp.recv(socket, 0, 5000)
      read_headers(socket, acc <> data)
    end
  end
end
