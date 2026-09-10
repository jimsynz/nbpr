defmodule NBPR.OCI.RegistryPush do
  @moduledoc false

  alias NBPR.OCI.{Client, Push}

  def push!(prefix, package, tag, tarball) do
    client =
      case Client.authorize(Client.new(prefix, package, "push,pull")) do
        {:ok, client} -> client
        {:error, reason} -> raise "registry authentication failed: #{inspect(reason)}"
      end

    data = File.read!(tarball)
    digest = digest(data)
    config_digest = digest("{}")
    upload_blob!(client, digest, data)
    upload_blob!(client, config_digest, "{}")

    manifest =
      Push.build_manifest(digest, byte_size(data), Path.basename(tarball), config_digest, 2)

    body =
      {"application/vnd.oci.image.manifest.v1+json", IO.iodata_to_binary(:json.encode(manifest))}

    expect!(
      Client.request(client, :put, "/v2/#{client.image}/manifests/#{tag}", [], body),
      [201],
      "manifest upload"
    )

    :ok
  end

  defp upload_blob!(client, digest, data) do
    path = "/v2/#{client.image}/blobs/uploads/"

    {headers, _} =
      expect!(
        Client.request(client, :post, path, [], {"application/octet-stream", ""}),
        [202],
        "blob upload init"
      )

    location =
      Client.header(headers, "location") ||
        raise "registry upload response has no Location header"

    url = client.base |> URI.merge(path) |> URI.merge(location) |> URI.to_string()
    url = Push.append_digest_param(url, digest)

    expect!(
      Client.request(client, :put, url, [], {"application/octet-stream", data}),
      [201],
      "blob upload"
    )
  end

  defp expect!({:ok, status, headers, body}, statuses, context) do
    if status in statuses,
      do: {headers, body},
      else: raise("registry #{context} failed (HTTP #{status})")
  end

  defp expect!({:error, reason}, _, context),
    do: raise("registry #{context} failed: #{inspect(reason)}")

  defp digest(data), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, data), case: :lower)
end
