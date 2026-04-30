defmodule Mix.Tasks.Nbpr.Fetch do
  @shortdoc "Fetch and stage nbpr package artefacts for the current target"

  @moduledoc """
  Walks the user's loaded applications for nbpr packages, fetches each one's
  artefact tarball for the active Nerves system (if not already cached),
  extracts it, and stages each artefact's `target/` directory into
  `:nerves, :firmware, :extra_rootfs_overlays`.

      mix nbpr.fetch

  Intended to run before `mix firmware`. The recommended wiring is:

      aliases: ["firmware": ["nbpr.fetch", "firmware"]]

  ## Discovery

  An nbpr package is detected by:

  1. Its application name starts with `nbpr_`.
  2. The corresponding `NBPR.<Camel>` module exports `__nbpr_package__/0`.

  ## Required environment

  Must be run with `MIX_TARGET` set to a real Nerves target — there's no work
  to do for `:host`. The active Nerves system and version are read from
  `Nerves.Env.system/0`.
  """

  use Mix.Task

  alias NBPR.Artifact
  alias NBPR.Artifact.{Cache, Fetcher}

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("loadpaths", [])

    if Mix.target() == :host do
      Mix.raise("mix nbpr.fetch must run with a real MIX_TARGET; got :host")
    end

    system_app = system_app!()
    system_version = system_version!(system_app)
    packages = discover_packages()

    case packages do
      [] ->
        Mix.shell().info("[nbpr] no nbpr packages in deps; nothing to fetch.")
        :ok

      packages ->
        overlays =
          Enum.map(packages, fn {app, module} ->
            fetch_one(app, module, system_app, system_version)
          end)

        apply_overlays(overlays)

        Mix.shell().info(
          "[nbpr] staged #{length(overlays)} overlay(s) for #{system_app} #{system_version}."
        )
    end
  end

  @doc false
  @spec derive_module(String.t() | atom()) :: module()
  def derive_module(app) when is_atom(app), do: derive_module(Atom.to_string(app))

  def derive_module(app_name) when is_binary(app_name) do
    short = String.replace_prefix(app_name, "nbpr_", "")
    Module.concat(["NBPR", Macro.camelize(short)])
  end

  @doc false
  @spec apply_overlays([Path.t()]) :: :ok
  def apply_overlays(overlays) do
    firmware = Application.get_env(:nerves, :firmware, [])
    existing = Keyword.get(firmware, :extra_rootfs_overlays, [])
    merged = Keyword.put(firmware, :extra_rootfs_overlays, existing ++ overlays)
    Application.put_env(:nerves, :firmware, merged)
  end

  defp system_app! do
    case Code.ensure_loaded?(Nerves.Env) and Nerves.Env.system() do
      false ->
        Mix.raise("Nerves.Env is not loaded; ensure :nerves is a project dep")

      nil ->
        Mix.raise(
          "no Nerves system found for target #{inspect(Mix.target())}; " <>
            "ensure the right `nerves_system_*` dep is in mix.exs"
        )

      %{app: app} ->
        app
    end
  end

  defp system_version!(system_app) do
    case Application.spec(system_app, :vsn) do
      nil -> Mix.raise("could not read version of #{inspect(system_app)}")
      vsn -> to_string(vsn)
    end
  end

  defp discover_packages do
    for {app, _, _} <- Application.loaded_applications(),
        app != :nbpr,
        app_name = Atom.to_string(app),
        String.starts_with?(app_name, "nbpr_"),
        module = derive_module(app_name),
        Code.ensure_loaded?(module),
        function_exported?(module, :__nbpr_package__, 0),
        do: {app, module}
  end

  defp fetch_one(app, module, system_app, system_version) do
    pkg = module.__nbpr_package__()
    package_version = to_string(Application.spec(app, :vsn))

    inputs = %{
      package_name: Atom.to_string(app),
      package_version: package_version,
      system_app: system_app,
      system_version: system_version,
      build_opts: Application.get_env(app, :build_opts, [])
    }

    unless Cache.valid?(inputs) do
      Mix.shell().info("[nbpr] fetching #{inputs.package_name}-#{package_version}...")
      tarball = Fetcher.fetch!(inputs, pkg.artifact_sites)
      :ok = Cache.extract!(tarball, inputs)
    end

    Path.join(Artifact.cache_dir(inputs), "target")
  end
end
