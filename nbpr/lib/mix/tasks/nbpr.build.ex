defmodule Mix.Tasks.Nbpr.Build do
  @shortdoc "Source-build an NBPR package via Buildroot"

  @moduledoc """
  Builds an NBPR package from source against the active Nerves system's
  Buildroot tree, then packs the result into a canonical artefact tarball.

      mix nbpr.build NBPR.Jq [-o /output/dir]

  ## What it does

  1. Reads `__nbpr_package__/0` on the supplied module.
  2. Discovers `deps/nerves_system_br/` and reads the pinned BR version.
  3. Ensures the BR source tree is downloaded, extracted, and patched at
     `$NERVES_DATA_DIR/nbpr/buildroot/<version>/` (caching across runs).
  4. Renders a defconfig that layers the package + its `build_opts` on top
     of the active system's defconfig (e.g. `nerves_defconfig`).
  5. Runs `make olddefconfig` and `make <br_package>-rebuild` against a
     fresh `O=<tmp>` output dir, with `BR2_DL_DIR` pointing at the shared
     download cache.
  6. Harvests `<O>/per-package/<br_package>/{target,staging}` and packs
     into `<output_dir>/<package>-<version>-<system>-<system_version>-<key>.tar.gz`.

  ## Required environment

  - `MIX_TARGET` set to a real Nerves target (not `:host`).
  - `deps/nerves_system_br/` and `deps/<system>/` resolved (`mix deps.get`).
  - Linux host (Docker support is queued for Phase 4.5).

  ## Flags

    * `-o`, `--output` — directory for the produced tarball.
      Defaults to `<build_path>/nbpr/`.
    * `--build-opts key=value,...` — explicit build options for the package.
      Defaults are read from the package's schema if omitted.
  """

  use Mix.Task

  alias NBPR.Buildroot
  alias NBPR.Buildroot.{Build, Defconfig, Harvest, Source}
  alias NBPR.Pack

  @requirements ["app.config"]

  @switches [output: :string, build_opts: :string]
  @aliases [o: :output]

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    module_name = parse_positional!(positional)
    module = Module.concat([module_name])

    unless Code.ensure_loaded?(module) and function_exported?(module, :__nbpr_package__, 0) do
      Mix.raise("#{inspect(module)} is not an NBPR package (no `__nbpr_package__/0`)")
    end

    if Mix.target() == :host do
      Mix.raise("mix nbpr.build must run with a real MIX_TARGET; got :host")
    end

    pkg = module.__nbpr_package__()
    {system_app, system_version} = active_system!()
    output_dir = output_dir!(opts)
    build_opts = resolve_build_opts(pkg, opts)

    inputs = %{
      package_name: "nbpr_#{pkg.name}",
      package_version: package_version!(pkg),
      system_app: system_app,
      system_version: system_version,
      build_opts: build_opts
    }

    Mix.shell().info("[nbpr] building #{inputs.package_name} #{inputs.package_version}")

    br_source = ensure_br_source!()
    system_source_path = system_source_path!(system_app)

    {:ok, nerves_system_br_path} = Buildroot.nerves_system_br_path()

    {:ok, br_version} = Buildroot.br_version(nerves_system_br_path)
    output_dir_br = stable_output_dir(system_app, br_version)

    defconfig_text = render_defconfig!(pkg, system_source_path, build_opts)

    extra_env = [
      # Nerves' BR patches add support for `${NERVES_DEFCONFIG_DIR}` so paths
      # in the target system's `nerves_defconfig` (notably `BR2_GLOBAL_PATCH_DIR`)
      # resolve to the target-system source dir.
      {"NERVES_DEFCONFIG_DIR", system_source_path},
      # `BR2_EXTERNAL` points at Nerves' BR external tree (`nerves_system_br`,
      # which contains erlinit/nerves-config/boardid/etc.). The per-target
      # system (e.g. `nerves_system_rpi4`) is NOT a BR external tree — it just
      # carries the defconfig + patches.
      {"BR2_EXTERNAL", nerves_system_br_path}
    ]

    # Bind-mount the workspace deps so `NERVES_DEFCONFIG_DIR` and
    # `BR2_EXTERNAL` paths inside the container resolve to the same source
    # trees they do on the host.
    deps_path = Mix.Project.deps_path()

    Build.build!(br_source, output_dir_br, defconfig_text, pkg.br_package, extra_env,
      extra_mounts: [deps_path]
    )

    sources = Harvest.harvest!(output_dir_br, pkg.br_package)
    tarball = Pack.pack!(inputs, sources, output_dir)

    Mix.shell().info("[nbpr] packed #{tarball}")
    tarball
  end

  # Stable per-(system, BR-version) output dir. Reusing across builds keeps
  # toolchain extraction + host-skeleton + other unchanging packages around;
  # `make olddefconfig` reconciles defconfig drift between builds.
  defp stable_output_dir(system_app, br_version) do
    Path.join([
      data_dir(),
      "nbpr",
      "build",
      "#{system_app}-#{br_version}"
    ])
  end

  defp data_dir do
    cond do
      dir = System.get_env("NERVES_ARTIFACTS_DIR") ->
        dir

      true ->
        base =
          System.get_env("XDG_DATA_HOME") ||
            Path.join(System.user_home!(), ".local/share")

        Path.join(base, "nerves")
    end
  end

  defp parse_positional!([module]), do: module
  defp parse_positional!(_), do: Mix.raise("usage: mix nbpr.build <Module> [-o <dir>]")

  defp active_system! do
    unless Code.ensure_loaded?(Nerves.Env) do
      Mix.raise("Nerves.Env not loaded; ensure :nerves is a project dep")
    end

    case apply(Nerves.Env, :system, []) do
      nil ->
        Mix.raise("no Nerves system found for target #{inspect(Mix.target())}")

      %{app: app} ->
        version =
          case Application.spec(app, :vsn) do
            nil -> Mix.raise("could not read version of #{inspect(app)}")
            vsn -> to_string(vsn)
          end

        {app, version}
    end
  end

  defp package_version!(pkg) do
    package_app = String.to_atom("nbpr_#{pkg.name}")

    case Application.spec(package_app, :vsn) do
      nil -> Mix.raise("could not read version of #{inspect(package_app)}")
      vsn -> to_string(vsn)
    end
  end

  defp output_dir!(opts) do
    dir = opts[:output] || Path.join([Mix.Project.build_path(), "nbpr"])
    File.mkdir_p!(dir)
    dir
  end

  defp resolve_build_opts(pkg, opts) do
    if opts[:build_opts] do
      parse_cli_build_opts(opts[:build_opts])
    else
      defaults_for(pkg)
    end
  end

  defp parse_cli_build_opts(""), do: []

  defp parse_cli_build_opts(string) do
    string
    |> String.split(",", trim: true)
    |> Enum.map(fn entry ->
      case String.split(entry, "=", parts: 2) do
        [k, v] -> {String.to_atom(k), parse_value(v)}
        _ -> Mix.raise("invalid --build-opts entry #{inspect(entry)}; expected key=value")
      end
    end)
  end

  defp parse_value("true"), do: true
  defp parse_value("false"), do: false

  defp parse_value(v) do
    case Integer.parse(v) do
      {int, ""} -> int
      _ -> v
    end
  end

  defp defaults_for(pkg) do
    case NimbleOptions.validate([], pkg.build_opts) do
      {:ok, defaults} -> defaults
      {:error, _} -> []
    end
  end

  defp ensure_br_source! do
    {:ok, system_br_path} = require_nerves_system_br!()
    {:ok, br_version} = require_br_version!(system_br_path)
    {:ok, patches_dir} = require_patches!(system_br_path)

    Mix.shell().info(
      "[nbpr] ensuring BR #{br_version} source cache (one-time download if needed)"
    )

    Source.ensure!(br_version, patches_dir)
  end

  defp require_nerves_system_br! do
    case Buildroot.nerves_system_br_path() do
      {:ok, path} ->
        {:ok, path}

      {:error, _} ->
        Mix.raise(
          "deps/nerves_system_br not found; run `mix deps.get` first or check your mix.exs"
        )
    end
  end

  defp require_br_version!(system_br_path) do
    case Buildroot.br_version(system_br_path) do
      {:ok, version} -> {:ok, version}
      {:error, reason} -> Mix.raise("could not read BR version: #{inspect(reason)}")
    end
  end

  defp require_patches!(system_br_path) do
    case Buildroot.patches_path(system_br_path) do
      {:ok, dir} -> {:ok, dir}
      {:error, _} -> Mix.raise("BR patches dir missing at #{system_br_path}/patches/buildroot")
    end
  end

  defp system_source_path!(system_app) do
    path = Path.join(Mix.Project.deps_path(), Atom.to_string(system_app))

    unless File.dir?(path) do
      Mix.raise("system source not found at #{path}; ensure `mix deps.get` ran")
    end

    path
  end

  defp render_defconfig!(pkg, system_source_path, build_opts) do
    sys_defconfig = Path.join(system_source_path, "nerves_defconfig")

    unless File.regular?(sys_defconfig) do
      Mix.raise("system defconfig not found at #{sys_defconfig}")
    end

    Defconfig.render!(pkg, sys_defconfig, build_opts)
  end
end
