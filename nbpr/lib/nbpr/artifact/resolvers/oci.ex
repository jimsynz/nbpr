defmodule NBPR.Artifact.Resolvers.OCI do
  @moduledoc """
  OCI Distribution registry resolver, including self-hosted Forgejo registries.

  Sites use `{:oci, "forgejo.example.com/<owner>[/<path>]"}`. HTTPS is the
  default; an explicit `http://` prefix supports local development registries.
  Basic and same-origin Bearer token authentication are supported. Project
  credentials come from `NBPR_REGISTRY_USERNAME` and `NBPR_REGISTRY_TOKEN`.
  """

  @behaviour NBPR.Artifact.Resolver
  alias NBPR.Artifact.Resolvers.GHCR
  alias NBPR.OCI.Client

  @manifest_type "application/vnd.oci.image.manifest.v1+json"
  @layer_type "application/vnd.nbpr.tarball.v1+tar+gzip"

  @impl true
  def plan({:oci, prefix}, inputs) do
    Client.parse_prefix!(prefix)
    {__MODULE__, %{prefix: prefix, package: inputs.package_name, tag: GHCR.tag_for(inputs)}}
  end

  def plan(_, _), do: nil

  @impl true
  def get(plan, dest) do
    client = Client.new(plan.prefix, plan.package)

    with {:ok, 200, _, body} <-
           Client.request(client, :get, manifest_path(client, plan.tag), [
             {"accept", @manifest_type}
           ]),
         {:ok, digest} <- layer_digest(body),
         {:ok, 200, _, data} <-
           Client.request(client, :get, "/v2/#{client.image}/blobs/#{digest}"),
         :ok <- verify_digest(data, digest),
         :ok <- File.mkdir_p(Path.dirname(dest)),
         :ok <- File.write(dest, data) do
      :ok
    else
      {:ok, status, _, _} -> {:error, {:registry_http_status, status}}
      {:error, _} = error -> error
    end
  end

  def tag_exists?(plan) do
    client = Client.new(plan.prefix, plan.package)

    case Client.request(client, :head, manifest_path(client, plan.tag), [
           {"accept", @manifest_type}
         ]) do
      {:ok, 200, _, _} -> {:ok, true}
      {:ok, 404, _, _} -> {:ok, false}
      {:ok, status, _, _} -> {:error, {:manifest_http, status}}
      error -> error
    end
  end

  defp manifest_path(client, tag), do: "/v2/#{client.image}/manifests/#{tag}"

  defp layer_digest(body) do
    case :json.decode(body) do
      %{"layers" => layers} when is_list(layers) ->
        case Enum.find(layers, &(is_map(&1) and &1["mediaType"] == @layer_type)) do
          %{"digest" => "sha256:" <> hash = digest} when byte_size(hash) == 64 ->
            if Regex.match?(~r/\A[0-9a-f]{64}\z/, hash),
              do: {:ok, digest},
              else: {:error, :invalid_layer_digest}

          _ ->
            {:error, :no_nbpr_layer}
        end

      _ ->
        {:error, :malformed_manifest}
    end
  rescue
    _ -> {:error, :malformed_manifest}
  end

  defp verify_digest(data, digest) do
    actual = "sha256:" <> Base.encode16(:crypto.hash(:sha256, data), case: :lower)
    if actual == digest, do: :ok, else: {:error, :blob_digest_mismatch}
  end
end
