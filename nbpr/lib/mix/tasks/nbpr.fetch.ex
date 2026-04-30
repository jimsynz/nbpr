defmodule Mix.Tasks.Nbpr.Fetch do
  @shortdoc "Fetch and stage nbpr package artefacts for the current target"

  @moduledoc """
  Walks the user's loaded applications for nbpr packages, fetches each one's
  artefact tarball for the active Nerves system (if not already cached), and
  copies the artefact's `target/` contents into the package's `priv/` so it
  ships as part of the OTP release.

      mix nbpr.fetch

  Intended to run before `mix firmware`. Recommended wiring:

      aliases: ["firmware": ["nbpr.fetch", "firmware"]]

  ## Why `priv/` instead of a rootfs overlay

  Each nbpr package's binaries and shared libraries land at
  `<release>/lib/nbpr_<name>-<vsn>/priv/usr/...`. `:code.priv_dir/1`
  resolves the right place at runtime; `NBPR.Application` sets
  `PATH` and `LD_LIBRARY_PATH` once at boot so child processes find
  binaries and inter-package shared libraries. This keeps Mix release
  semantics intact and avoids two packages stomping on each other in
  the rootfs.

  ## Discovery

  An nbpr package is detected by:

  1. Its application name starts with `nbpr_`.
  2. The corresponding `NBPR.<Camel>` module exports `__nbpr_package__/0`.

  ## Required environment

  Must be run with `MIX_TARGET` set to a real Nerves target — there's no
  work to do for `:host`. The active Nerves system and version are read
  from `Nerves.Env.system/0`.
  """

  use Mix.Task

  alias NBPR.Artifact
  alias NBPR.Artifact.{Cache, Fetcher}
  alias NBPR.Buildroot.Builder

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
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
        Enum.each(packages, fn {app, module} ->
          install_to_priv!(app, module, system_app, system_version)
        end)

        Mix.shell().info(
          "[nbpr] installed #{length(packages)} package(s) into priv for " <>
            "#{system_app} #{system_version}."
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
  @spec priv_dir_for(atom()) :: Path.t()
  def priv_dir_for(app) when is_atom(app) do
    Path.join([Mix.Project.build_path(), "lib", Atom.to_string(app), "priv"])
  end

  @doc false
  @spec build_rootfs_overlay_dir() :: Path.t()
  def build_rootfs_overlay_dir do
    Path.join([Mix.Project.build_path(), "nerves", "rootfs_overlay"])
  end

  defp system_app! do
    unless Code.ensure_loaded?(Nerves.Env) do
      Mix.raise("Nerves.Env is not loaded; ensure :nerves is a project dep")
    end

    case apply(Nerves.Env, :system, []) do
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

  defp install_to_priv!(app, module, system_app, system_version) do
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
      tarball = fetch_or_build!(pkg, inputs)
      :ok = Cache.extract!(tarball, inputs)
    end

    cache_dir = Artifact.cache_dir(inputs)

    install_target!(cache_dir, app)
    install_rootfs!(cache_dir)
  end

  defp fetch_or_build!(pkg, inputs) do
    Mix.shell().info(
      "[nbpr] fetching #{inputs.package_name}-#{inputs.package_version}..."
    )

    try do
      Fetcher.fetch!(inputs, pkg.artifact_sites)
    rescue
      e in RuntimeError ->
        Mix.shell().info(
          "[nbpr] no prebuilt artefact found; falling back to source-build"
        )

        Mix.shell().info("[nbpr] (fetch error: #{first_line(Exception.message(e))})")

        output_dir = Path.join(Mix.Project.build_path(), "nbpr")
        Builder.build!(pkg, inputs, output_dir)
    end
  end

  defp first_line(msg) do
    msg |> String.split("\n", trim: true) |> List.first() || msg
  end

  defp install_target!(cache_dir, app) do
    target_src = Path.join(cache_dir, "target")

    if File.dir?(target_src) do
      priv_dest = priv_dir_for(app)
      File.mkdir_p!(priv_dest)
      File.cp_r!(target_src, priv_dest)
    end
  end

  defp install_rootfs!(cache_dir) do
    rootfs_src = Path.join(cache_dir, "rootfs")

    if File.dir?(rootfs_src) do
      overlay_dest = build_rootfs_overlay_dir()
      File.mkdir_p!(overlay_dest)
      File.cp_r!(rootfs_src, overlay_dest)
    end
  end
end
