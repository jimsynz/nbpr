defmodule NBPR.OCI.Push do
  @moduledoc """
  Pure-Elixir OCI artefact push to ghcr.io.

  Implements just enough of the OCI Distribution Spec push flow to publish
  one nbpr tarball as an OCI image manifest with a single layer:

    1. Auth: `GET /token` with Basic auth (`<username>:<token>`) and scope
       `repository:<image>:push,pull` → bearer token.
    2. For each blob (the tarball layer + the empty config object):
       `POST /v2/<image>/blobs/uploads/` (Bearer) → 202 with `Location:`
       upload URL → `PUT <upload-url>?digest=sha256:<hex>` (Bearer, body) → 201.
    3. `PUT /v2/<image>/manifests/<tag>` (Bearer, JSON body, manifest
       Content-Type) → 201.

  ## Credentials

  Reads from `GHCR_TOKEN` (preferred) or `GITHUB_TOKEN` env vars. The
  username is from `GHCR_USERNAME`, defaulting to `"oauth"` (irrelevant
  for token-based auth — the registry validates the token, not the user).

  In GitHub Actions, `GITHUB_TOKEN` is auto-injected; setting `GHCR_USERNAME`
  to `${{ github.actor }}` is conventional but not required.
  """

  alias NBPR.Artifact.HTTP

  @manifest_media_type "application/vnd.oci.image.manifest.v1+json"
  @layer_media_type "application/vnd.nbpr.tarball.v1+tar+gzip"
  @artifact_type "application/vnd.nbpr.artifact.v1"
  @empty_config_media_type "application/vnd.oci.empty.v1+json"
  @empty_config_data "{}"

  @doc """
  Pushes `tarball_path` to `ghcr.io/<image>:<tag>` as an OCI artefact.

  Raises on any HTTP failure with the registry's error body included.
  """
  @spec push!(String.t(), String.t(), Path.t()) :: :ok
  def push!(image, tag, tarball_path) do
    HTTP.start_apps!()

    {username, password} = credentials!()
    bearer = fetch_push_token!(image, username, password)

    layer_data = File.read!(tarball_path)
    layer_digest = "sha256:" <> sha256_hex(layer_data)
    layer_size = byte_size(layer_data)

    config_digest = "sha256:" <> sha256_hex(@empty_config_data)
    config_size = byte_size(@empty_config_data)

    upload_blob!(image, bearer, layer_digest, layer_data)
    upload_blob!(image, bearer, config_digest, @empty_config_data)

    manifest =
      build_manifest(
        layer_digest,
        layer_size,
        Path.basename(tarball_path),
        config_digest,
        config_size
      )

    upload_manifest!(image, tag, bearer, manifest)
    :ok
  end

  @doc false
  @spec build_manifest(String.t(), non_neg_integer(), String.t(), String.t(), non_neg_integer()) ::
          map()
  def build_manifest(layer_digest, layer_size, layer_filename, config_digest, config_size) do
    %{
      "schemaVersion" => 2,
      "mediaType" => @manifest_media_type,
      "artifactType" => @artifact_type,
      "config" => %{
        "mediaType" => @empty_config_media_type,
        "digest" => config_digest,
        "size" => config_size,
        "data" => Base.encode64(@empty_config_data)
      },
      "layers" => [
        %{
          "mediaType" => @layer_media_type,
          "digest" => layer_digest,
          "size" => layer_size,
          "annotations" => %{
            "org.opencontainers.image.title" => layer_filename
          }
        }
      ],
      "annotations" => %{
        "org.opencontainers.image.created" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  defp credentials! do
    username = System.get_env("GHCR_USERNAME") || "oauth"

    token =
      System.get_env("GHCR_TOKEN") ||
        System.get_env("GITHUB_TOKEN") ||
        raise "GHCR_TOKEN or GITHUB_TOKEN env var required to push to ghcr.io"

    {username, token}
  end

  defp fetch_push_token!(image, username, password) do
    url = "https://ghcr.io/token?service=ghcr.io&scope=repository:#{image}:push,pull"
    basic = Base.encode64("#{username}:#{password}")

    headers = [
      {~c"authorization", String.to_charlist("Basic " <> basic)}
    ]

    case :httpc.request(:get, {String.to_charlist(url), headers}, [autoredirect: true], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        case :json.decode(IO.iodata_to_binary(body)) do
          %{"token" => token} when is_binary(token) -> token
          other -> raise "no token in response: #{inspect(other)}"
        end

      {:ok, {{_, status, _}, _, body}} ->
        raise "token fetch failed (#{status}): #{IO.iodata_to_binary(body)}"

      {:error, reason} ->
        raise "token fetch error: #{inspect(reason)}"
    end
  end

  defp upload_blob!(image, bearer, digest, data) do
    init_url = "https://ghcr.io/v2/#{image}/blobs/uploads/"

    init_headers = [
      {~c"authorization", String.to_charlist("Bearer " <> bearer)},
      {~c"content-length", ~c"0"}
    ]

    upload_url =
      case :httpc.request(
             :post,
             {String.to_charlist(init_url), init_headers, ~c"application/octet-stream", ""},
             [autoredirect: false],
             []
           ) do
        {:ok, {{_, 202, _}, headers, _}} ->
          location_header!(headers, init_url)

        {:ok, {{_, status, _}, _, body}} ->
          raise "blob upload init failed (#{status}): #{IO.iodata_to_binary(body)}"

        {:error, reason} ->
          raise "blob upload init error: #{inspect(reason)}"
      end

    put_url = append_digest_param(upload_url, digest)

    put_headers = [
      {~c"authorization", String.to_charlist("Bearer " <> bearer)}
    ]

    case :httpc.request(
           :put,
           {String.to_charlist(put_url), put_headers, ~c"application/octet-stream", data},
           [autoredirect: false],
           []
         ) do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 ->
        :ok

      {:ok, {{_, status, _}, _, body}} ->
        raise "blob PUT failed (#{status}) for #{digest}: #{IO.iodata_to_binary(body)}"

      {:error, reason} ->
        raise "blob PUT error for #{digest}: #{inspect(reason)}"
    end
  end

  defp upload_manifest!(image, tag, bearer, manifest) do
    url = "https://ghcr.io/v2/#{image}/manifests/#{tag}"
    body = IO.iodata_to_binary(:json.encode(manifest))

    headers = [
      {~c"authorization", String.to_charlist("Bearer " <> bearer)}
    ]

    case :httpc.request(
           :put,
           {String.to_charlist(url), headers, String.to_charlist(@manifest_media_type), body},
           [autoredirect: false],
           []
         ) do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 ->
        :ok

      {:ok, {{_, status, _}, _, body}} ->
        raise "manifest PUT failed (#{status}): #{IO.iodata_to_binary(body)}"

      {:error, reason} ->
        raise "manifest PUT error: #{inspect(reason)}"
    end
  end

  @doc false
  @spec append_digest_param(String.t(), String.t()) :: String.t()
  def append_digest_param(url, digest) do
    sep = if String.contains?(url, "?"), do: "&", else: "?"
    url <> sep <> "digest=" <> URI.encode_www_form(digest)
  end

  defp location_header!(headers, base_url) do
    case :proplists.get_value(~c"location", headers) do
      :undefined ->
        raise "no Location header in upload init response"

      value ->
        value = to_string(value)

        if String.starts_with?(value, "http://") or String.starts_with?(value, "https://") do
          value
        else
          base_url
          |> URI.parse()
          |> Map.put(:path, value)
          |> URI.to_string()
          |> resolve_relative(value, base_url)
        end
    end
  end

  defp resolve_relative(_combined, value, base_url) do
    %URI{} = base = URI.parse(base_url)
    URI.merge(base, value) |> URI.to_string()
  end

  defp sha256_hex(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end
end
