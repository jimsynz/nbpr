defmodule Mix.Tasks.Nbpr.Build do
  @shortdoc "Source-build an NBPR package via Buildroot"

  @moduledoc """
  Builds an NBPR package from source against the active Nerves system's
  Buildroot tree, then packs the result into a canonical artefact tarball.

      mix nbpr.build NBPR.Jq [-o /output/dir]

  Thin CLI wrapper around `NBPR.Buildroot.Builder.build!/3` — `mix nbpr.fetch`
  uses the same orchestrator as a fallback when no prebuilt artefact is
  published for the active (system, system_version, build_opts) tuple.

  ## Required environment

  - `MIX_TARGET` set to a real Nerves target (not `:host`).
  - `deps/nerves_system_br/` and `deps/<system>/` resolved (`mix deps.get`).
  - Either Linux + inside `mix nerves.system.shell`, or `docker` on PATH
    (any host).

  ## Flags

    * `-o`, `--output` — directory for the produced tarball.
      Defaults to `<build_path>/nbpr/`.
    * `--build-opts key=value,...` — explicit build options for the package.
      Defaults are read from the package's schema if omitted.
  """

  use Mix.Task

  alias NBPR.Buildroot.Builder

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

    tarball = Builder.build!(pkg, inputs, output_dir)
    Mix.shell().info("[nbpr] packed #{tarball}")
    tarball
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
end
