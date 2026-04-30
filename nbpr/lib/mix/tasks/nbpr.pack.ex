defmodule Mix.Tasks.Nbpr.Pack do
  @shortdoc "Pack a directory of built files into a canonical nbpr artefact tarball"

  @moduledoc """
  Produces a canonical nbpr artefact tarball from already-built files on disk.

      mix nbpr.pack \\
          --package nbpr_jq \\
          --package-version 1.7.1 \\
          --system nerves_system_rpi4 \\
          --system-version 2.0.1 \\
          --target /path/to/built/target \\
          [--staging /path/to/built/staging] \\
          [--rootfs /path/to/built/rootfs] \\
          [--legal-info /path/to/built/legal-info] \\
          [--build-opts key=value,key2=value2] \\
          [-o /output/dir]

  Outputs a `<package>-<version>-<system>-<system-version>-<key>.tar.gz` in
  `-o` (defaults to `cwd`). The tarball follows the layout consumed by
  `NBPR.Artifact.Cache.extract!/2`.

  Useful for hand-built artefacts (you ran Buildroot yourself) and as a
  building block for the eventual `mix nbpr.build` task.
  """

  use Mix.Task

  @switches [
    package: :string,
    package_version: :string,
    system: :string,
    system_version: :string,
    target: :string,
    staging: :string,
    rootfs: :string,
    legal_info: :string,
    build_opts: :string,
    output: :string
  ]

  @aliases [o: :output]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    inputs = build_inputs!(opts)
    sources = build_sources!(opts)
    output_dir = Keyword.get(opts, :output, File.cwd!())

    tarball = NBPR.Pack.pack!(inputs, sources, output_dir)

    Mix.shell().info("[nbpr] packed #{tarball}")
    tarball
  end

  defp build_inputs!(opts) do
    package = Keyword.fetch!(opts, :package) |> validate_required!(:package)

    package_version =
      Keyword.fetch!(opts, :package_version) |> validate_required!(:package_version)

    system = Keyword.fetch!(opts, :system) |> validate_required!(:system)

    system_version =
      Keyword.fetch!(opts, :system_version) |> validate_required!(:system_version)

    %{
      package_name: package,
      package_version: package_version,
      system_app: String.to_atom(system),
      system_version: system_version,
      build_opts: parse_build_opts(opts[:build_opts])
    }
  rescue
    KeyError ->
      Mix.raise(
        "missing required option; need --package, --package-version, --system, --system-version"
      )
  end

  defp build_sources!(opts) do
    %{}
    |> maybe_add(:target, opts[:target])
    |> maybe_add(:staging, opts[:staging])
    |> maybe_add(:rootfs, opts[:rootfs])
    |> maybe_add(:legal_info, opts[:legal_info])
    |> case do
      sources when map_size(sources) == 0 ->
        Mix.raise("at least one of --target, --staging, --rootfs, --legal-info must be provided")

      sources ->
        sources
    end
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, path), do: Map.put(map, key, path)

  defp validate_required!(value, _key) when is_binary(value) and value != "", do: value

  defp validate_required!(_value, key) do
    Mix.raise("--#{key |> to_string() |> String.replace("_", "-")} cannot be empty")
  end

  defp parse_build_opts(nil), do: []
  defp parse_build_opts(""), do: []

  defp parse_build_opts(string) when is_binary(string) do
    string
    |> String.split(",", trim: true)
    |> Enum.map(&parse_build_opt/1)
  end

  defp parse_build_opt(pair) do
    case String.split(pair, "=", parts: 2) do
      [key, value] -> {String.to_atom(key), parse_build_opt_value(value)}
      _ -> Mix.raise("invalid --build-opts entry #{inspect(pair)}; expected key=value")
    end
  end

  defp parse_build_opt_value("true"), do: true
  defp parse_build_opt_value("false"), do: false

  defp parse_build_opt_value(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end
end
