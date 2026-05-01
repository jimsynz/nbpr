defmodule NBPR.Artifact.Resolvers.GHCR do
  @moduledoc """
  Resolver for `{:ghcr, "ghcr.io/<owner>"}` site specs.

  Each nbpr package maps to one OCI image at `ghcr.io/<owner>/<package_name>`.
  Build variants (package version, system, system-version, build-opts) become
  tags. Anonymous pull works for packages flipped to public visibility — the
  resolver does not authenticate.

  Wire flow per fetch:

  1. `GET /token?service=ghcr.io&scope=repository:<image>:pull` → anonymous JWT
  2. `GET /v2/<image>/manifests/<tag>` (Bearer + Accept manifest media type) → manifest JSON
  3. Pick the first layer whose mediaType matches `application/vnd.nbpr.tarball.v1+tar+gzip`
  4. `GET /v2/<image>/blobs/<digest>` (Bearer, autoredirect) → bytes streamed to disk
  """

  @behaviour NBPR.Artifact.Resolver

  alias NBPR.Artifact
  alias NBPR.Artifact.HTTP

  @manifest_media_type "application/vnd.oci.image.manifest.v1+json"
  @nbpr_layer_media_type "application/vnd.nbpr.tarball.v1+tar+gzip"

  @impl NBPR.Artifact.Resolver
  def plan({:ghcr, "ghcr.io/" <> owner}, %{} = inputs) when owner != "" do
    {__MODULE__,
     %{
       image: "#{owner}/#{inputs.package_name}",
       tag: tag_for(inputs)
     }}
  end

  def plan(_site, _inputs), do: nil

  @impl NBPR.Artifact.Resolver
  def get(%{image: image, tag: tag}, dest_path) do
    HTTP.start_apps!()

    with :ok <- File.mkdir_p(Path.dirname(dest_path)),
         {:ok, token} <- fetch_token(image),
         {:ok, manifest} <- fetch_manifest(image, tag, token),
         {:ok, digest} <- find_layer_digest(manifest),
         :ok <- fetch_blob(image, digest, token, dest_path) do
      :ok
    end
  end

  @doc false
  @spec tag_for(Artifact.build_inputs()) :: String.t()
  def tag_for(%{} = inputs) do
    "#{inputs.package_version}-#{inputs.system_app}-#{inputs.system_version}-#{Artifact.cache_key(inputs)}"
  end

  @doc """
  Checks anonymously whether `<image>:<tag>` already has a manifest published.

  Returns `{:ok, true}` for HTTP 200, `{:ok, false}` for HTTP 404, and
  `{:error, reason}` for other failures (auth, network, malformed JSON).
  Uses the same anonymous-pull token flow as `get/2`, so packages need
  `public` visibility on GHCR for this to work without credentials.

  Used by `mix nbpr.publish` to short-circuit when the artefact's tag is
  already published — NBPR's cache-key model treats published tarballs as
  immutable, so re-pushing the same key is wasted work.
  """
  @spec tag_exists?(String.t(), String.t()) ::
          {:ok, boolean()} | {:error, term()}
  def tag_exists?(image, tag) when is_binary(image) and is_binary(tag) do
    NBPR.Artifact.HTTP.start_apps!()

    with {:ok, token} <- fetch_token(image),
         {:ok, status} <- head_manifest_status(image, tag, token) do
      case status do
        200 -> {:ok, true}
        404 -> {:ok, false}
        other -> {:error, {:manifest_http, other}}
      end
    end
  end

  defp head_manifest_status(image, tag, token) do
    url = "https://ghcr.io/v2/#{image}/manifests/#{tag}" |> String.to_charlist()

    headers = [
      {~c"authorization", String.to_charlist("Bearer " <> token)},
      {~c"accept", String.to_charlist(@manifest_media_type)}
    ]

    case :httpc.request(:head, {url, headers}, [autoredirect: true], []) do
      {:ok, {{_, status, _}, _, _}} -> {:ok, status}
      {:error, reason} -> {:error, {:manifest_fetch, reason}}
    end
  end

  defp fetch_token(image) do
    url =
      "https://ghcr.io/token?service=ghcr.io&scope=repository:#{image}:pull"
      |> String.to_charlist()

    case :httpc.request(:get, {url, []}, [autoredirect: true], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        case decode_json(body) do
          {:ok, %{"token" => token}} -> {:ok, token}
          {:ok, _other} -> {:error, :token_missing}
          {:error, _} = err -> err
        end

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:token_http, status}}

      {:error, reason} ->
        {:error, {:token_fetch, reason}}
    end
  end

  defp fetch_manifest(image, tag, token) do
    url = "https://ghcr.io/v2/#{image}/manifests/#{tag}" |> String.to_charlist()

    headers = [
      {~c"authorization", String.to_charlist("Bearer " <> token)},
      {~c"accept", String.to_charlist(@manifest_media_type)}
    ]

    case :httpc.request(:get, {url, headers}, [autoredirect: true], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        decode_json(body)

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:manifest_http, status}}

      {:error, reason} ->
        {:error, {:manifest_fetch, reason}}
    end
  end

  defp decode_json(body) do
    {:ok, :json.decode(IO.iodata_to_binary(body))}
  rescue
    e -> {:error, {:json_decode, e}}
  end

  defp find_layer_digest(%{"layers" => layers}) when is_list(layers) do
    case Enum.find(layers, &(&1["mediaType"] == @nbpr_layer_media_type)) do
      %{"digest" => digest} when is_binary(digest) -> {:ok, digest}
      _ -> {:error, :no_nbpr_layer}
    end
  end

  defp find_layer_digest(_), do: {:error, :malformed_manifest}

  defp fetch_blob(image, digest, token, dest_path) do
    url = "https://ghcr.io/v2/#{image}/blobs/#{digest}" |> String.to_charlist()
    headers = [{~c"authorization", String.to_charlist("Bearer " <> token)}]
    options = [stream: String.to_charlist(dest_path)]

    case :httpc.request(:get, {url, headers}, [autoredirect: true], options) do
      {:ok, :saved_to_file} ->
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        _ = File.rm(dest_path)
        {:error, {:blob_http, status}}

      {:error, reason} ->
        _ = File.rm(dest_path)
        {:error, {:blob_fetch, reason}}
    end
  end
end
