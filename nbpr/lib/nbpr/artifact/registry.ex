defmodule NBPR.Artifact.Registry do
  @moduledoc """
  Project registry used as a shared cache for source-built packages.

  Configure the registry in the consuming project's `config/config.exs`.
  It is searched before each package's declared sites. Publishing is opt-in:

      config :nbpr,
        registry: "forgejo.example.com/my-org/firmware",
        publish_after_build: true

  With publishing disabled (the default), the registry is a read-only cache.
  Set `NBPR_REGISTRY_USERNAME` and `NBPR_REGISTRY_TOKEN` for private Forgejo
  pulls and pushes. Credentials are sent only to the configured registry.
  HTTPS is the default; an explicit `http://` prefix is supported for local
  development. Basic and same-origin Bearer authentication are supported.

  A `ghcr.io/` prefix uses the existing GHCR backend and its `GHCR_TOKEN` /
  `GITHUB_TOKEN` credentials instead.
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

      prefix when is_binary(prefix) ->
        NBPR.OCI.Client.parse_prefix!(prefix)
        if String.starts_with?(prefix, "ghcr.io/"), do: {:ghcr, prefix}, else: {:oci, prefix}

      _ ->
        raise ArgumentError, "config :nbpr, :registry must be a host/<owner> prefix"
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

      {:oci, prefix} ->
        tag = GHCR.tag_for(inputs)
        push = Keyword.get(opts, :push, &NBPR.OCI.RegistryPush.push!/4)
        :ok = push.(prefix, inputs.package_name, tag, tarball)

        Mix.shell().info(
          "[nbpr] pushed #{Path.basename(tarball)} to #{prefix}/#{inputs.package_name}:#{tag}"
        )

      nil ->
        :ok
    end

    :ok
  end
end
