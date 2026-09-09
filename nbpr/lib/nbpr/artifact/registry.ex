defmodule NBPR.Artifact.Registry do
  @moduledoc """
  Project registry used as a shared cache for source-built packages.

  Configure the registry in the consuming project's `config/config.exs`.
  It is searched before each package's declared sites. Publishing is opt-in:

      config :nbpr,
        registry: "ghcr.io/my-org/firmware",
        publish_after_build: true

  With publishing disabled (the default), the registry is a read-only cache.
  """

  alias NBPR.Artifact.Resolvers.GHCR

  @doc "Returns project registry sites followed by the package's declared sites."
  def sites(package_sites) do
    case configured_site() do
      nil -> package_sites
      site -> Enum.uniq([site | package_sites])
    end
  end

  @doc false
  def configured_site do
    case Application.get_env(:nbpr, :registry) do
      nil ->
        nil

      "ghcr.io/" <> owner = prefix when owner != "" ->
        if Regex.match?(~r/\A[a-z0-9]+(?:[._\/-][a-z0-9]+)*\z/, owner) do
          {:ghcr, prefix}
        else
          raise ArgumentError,
                "registry must be a lowercase ghcr.io/<owner>[/<path>] prefix without a trailing slash"
        end

      _ ->
        raise ArgumentError, "config :nbpr, :registry must be a ghcr.io/<owner> prefix"
    end
  end

  @doc false
  def publish_site! do
    case Application.get_env(:nbpr, :publish_after_build, false) do
      false ->
        nil

      true ->
        configured_site() ||
          raise ArgumentError, "publish_after_build requires config :nbpr, :registry"

      _ ->
        raise ArgumentError, "config :nbpr, :publish_after_build must be a boolean"
    end
  end

  @doc "Publishes a newly built tarball when the project opts into cache writes."
  def publish_after_build!(inputs, tarball, opts \\ []) do
    case publish_site!() do
      {:ghcr, "ghcr.io/" <> owner} ->
        image = "#{owner}/#{inputs.package_name}"
        tag = GHCR.tag_for(inputs)
        push = Keyword.get(opts, :push, &NBPR.OCI.Push.push!/3)
        :ok = push.(image, tag, tarball)
        Mix.shell().info("[nbpr] pushed #{Path.basename(tarball)} to ghcr.io/#{image}:#{tag}")

      nil ->
        :ok
    end

    :ok
  end
end
