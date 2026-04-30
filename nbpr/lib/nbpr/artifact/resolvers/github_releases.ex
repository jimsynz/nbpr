defmodule NBPR.Artifact.Resolvers.GitHubReleases do
  @moduledoc """
  Resolver for `{:github_releases, "owner/repo"}` site specs.

  The release tag scheme is `<package>-v<version>`, so multiple packages can
  release independently from the same nbpr repository. The asset filename is
  the canonical tarball name from `NBPR.Artifact.tarball_name/1`.

  Public release assets only — no auth header. Auth (for private repos and
  rate-limit avoidance) can be layered on later, mirroring Nerves' GitHub
  resolver.
  """

  @behaviour NBPR.Artifact.Resolver

  alias NBPR.Artifact

  @impl NBPR.Artifact.Resolver
  def plan({:github_releases, owner_repo}, %{} = inputs) when is_binary(owner_repo) do
    {__MODULE__,
     %{
       url: build_url(owner_repo, inputs),
       owner_repo: owner_repo,
       tag: tag_for(inputs)
     }}
  end

  def plan(_site, _inputs), do: nil

  @impl NBPR.Artifact.Resolver
  def get(%{url: url}, dest_path) do
    with :ok <- File.mkdir_p(Path.dirname(dest_path)) do
      download(url, dest_path)
    end
  end

  @doc false
  @spec build_url(String.t(), Artifact.build_inputs()) :: String.t()
  def build_url(owner_repo, %{} = inputs) do
    "https://github.com/#{owner_repo}/releases/download/" <>
      "#{tag_for(inputs)}/#{Artifact.tarball_name(inputs)}"
  end

  defp tag_for(inputs) do
    "#{inputs.package_name}-v#{inputs.package_version}"
  end

  defp download(url, dest_path) do
    request = {String.to_charlist(url), []}
    http_options = [autoredirect: true]
    options = [stream: String.to_charlist(dest_path)]

    case :httpc.request(:get, request, http_options, options) do
      {:ok, :saved_to_file} ->
        :ok

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        _ = File.rm(dest_path)
        {:error, {:http_status, status}}

      {:error, reason} ->
        _ = File.rm(dest_path)
        {:error, reason}
    end
  end
end
