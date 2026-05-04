defmodule Mix.Tasks.Nbpr.Build do
  @shortdoc "Source-build an NBPR package via Buildroot"

  @moduledoc """
  Builds an NBPR package from source against the active Nerves system's
  Buildroot tree, then packs the result into a canonical artefact tarball.

      mix nbpr.build NBPR.Jq [-o /output/dir]

  Thin CLI wrapper around `NBPR.Buildroot.Builder.build!/3` — `mix nbpr.fetch`
  uses the same orchestrator as a fallback when no prebuilt artefact is
  published for the active (system, system_version, build_opts) tuple.

  ## Cache short-circuit

  Before kicking off a fresh source-build, the task HEADs the package's
  GHCR `{:ghcr, "ghcr.io/<owner>"}` site for the cache-key-derived tag.
  On a hit it downloads the prebuilt tarball into the output directory
  and skips the build entirely — the cache key encodes everything that
  affects the artefact (package version, system, system version, build
  opts), so a hit is by definition byte-identical to what we'd build.

  Pass `--force` to bypass the cache check (useful for verifying the
  build still works locally, or for re-publishing after a cache-key
  collision investigation).

  ## Required environment

  - `MIX_TARGET` set to a real Nerves target (not `:host`).
  - `deps/nerves_system_br/` and `deps/<system>/` resolved (`mix deps.get`).
  - Either Linux + inside `mix nerves.system.shell`, or `docker` on PATH
    (any host) — only needed when no cache hit is found.

  ## Flags

    * `-o`, `--output` — directory for the produced tarball.
      Defaults to `<build_path>/nbpr/`.
    * `--build-opts key=value,...` — explicit build options for the package.
      Defaults are read from the package's schema if omitted.
    * `--force` — skip the GHCR cache-hit check and always source-build.
  """

  use Mix.Task

  alias NBPR.Artifact
  alias NBPR.Artifact.Resolvers.GHCR
  alias NBPR.Buildroot.Builder

  @requirements ["app.config"]

  @switches [output: :string, build_opts: :string, force: :boolean]
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

    tarball =
      case maybe_reuse_cached(pkg, inputs, output_dir, opts[:force]) do
        {:ok, path} -> path
        :miss -> Builder.build!(pkg, inputs, output_dir)
      end

    Mix.shell().info("[nbpr] packed #{tarball}")
    tarball
  end

  # Returns `{:ok, tarball_path}` when a prebuilt artefact for this exact
  # input tuple is already on the package's GHCR site (and was successfully
  # downloaded), or `:miss` to fall through to a source-build.
  #
  # Any failure mode (no GHCR site declared, HEAD failure, 404, download
  # failure) is treated as a miss — the build path is the safe fallback,
  # and the cache check shouldn't itself become a cause of build failures.
  defp maybe_reuse_cached(_pkg, _inputs, _output_dir, true), do: :miss

  defp maybe_reuse_cached(pkg, inputs, output_dir, _force) do
    case ghcr_image(pkg) do
      nil ->
        :miss

      image ->
        tag = GHCR.tag_for(inputs)

        case GHCR.tag_exists?(image, tag) do
          {:ok, true} -> download_cached(image, tag, inputs, output_dir)
          {:ok, false} -> :miss
          {:error, reason} -> miss_with_warn("HEAD #{image}:#{tag} failed", reason)
        end
    end
  end

  defp ghcr_image(pkg) do
    case Enum.find(pkg.artifact_sites, &match?({:ghcr, "ghcr.io/" <> _}, &1)) do
      {:ghcr, "ghcr.io/" <> owner} -> "#{owner}/nbpr_#{pkg.name}"
      _ -> nil
    end
  end

  defp download_cached(image, tag, inputs, output_dir) do
    File.mkdir_p!(output_dir)
    dest = Path.join(output_dir, Artifact.tarball_name(inputs))

    case GHCR.get(%{image: image, tag: tag}, dest) do
      :ok ->
        Mix.shell().info("[nbpr] reused prebuilt #{image}:#{tag}")
        {:ok, dest}

      {:error, reason} ->
        miss_with_warn("download of #{image}:#{tag} failed", reason)
    end
  end

  defp miss_with_warn(context, reason) do
    Mix.shell().info("[nbpr] cache lookup: #{context} (#{inspect(reason)}); building fresh")
    :miss
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
