defmodule NBPR.Inspector do
  @moduledoc """
  Pretty-printer for `NBPR.Package` metadata.

  Used by `mix nbpr.inspect` and any future tooling that wants a human-readable
  summary of a package's contract.
  """

  alias NBPR.Package
  alias NBPR.Package.Daemon

  @spec format(Package.t()) :: String.t()
  def format(%Package{} = pkg) do
    [
      format_header(pkg),
      "",
      format_build_opts(pkg),
      "",
      format_daemons(pkg),
      "",
      format_kernel_modules(pkg),
      "",
      format_artifact_sites(pkg)
    ]
    |> Enum.join("\n")
  end

  defp format_header(%Package{} = pkg) do
    [
      "Package:        :nbpr_#{pkg.name}",
      "Module:         #{inspect(pkg.module)}",
      "Schema version: #{pkg.version}",
      "BR source:      #{br_source(pkg)}",
      "Description:    #{pkg.description}",
      "Homepage:       #{pkg.homepage || "(none)"}"
    ]
    |> Enum.join("\n")
  end

  defp br_source(%{br_package: pkg}) when is_binary(pkg), do: "#{pkg} (mainline Buildroot)"
  defp br_source(%{br_external_path: path}) when is_binary(path), do: "#{path} (vendored)"

  defp format_build_opts(%{build_opts: []}), do: "Build options: (none)"

  defp format_build_opts(%Package{} = pkg) do
    "Build options:\n" <>
      Enum.map_join(pkg.build_opts, "\n", fn {opt_name, spec} ->
        ext = Map.get(pkg.build_opt_extensions, opt_name, %{})
        format_build_opt(opt_name, spec, ext)
      end)
  end

  defp format_build_opt(opt_name, spec, ext) do
    summary = opt_summary(spec)

    [
      "  #{opt_name} (#{summary})",
      "    BR flag: #{Map.get(ext, :br_flag) || "(none)"}",
      spec[:doc] && "    #{spec[:doc]}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_daemons(%{daemons: []}), do: "Daemons: (none)"

  defp format_daemons(%{daemons: daemons}) do
    "Daemons:\n" <> Enum.map_join(daemons, "\n\n", &format_daemon/1)
  end

  defp format_daemon(%Daemon{} = daemon) do
    {mod, fun, _extras} = daemon.argv_template

    header = [
      "  #{daemon.name} → #{inspect(daemon.module)}",
      "    Path:           #{daemon.path}",
      "    Argv template:  #{inspect(mod)}.#{fun}"
    ]

    opt_lines =
      Enum.map(daemon.opts, fn {opt_name, spec} ->
        flag = Map.get(daemon.opt_flags, opt_name)
        format_runtime_opt(opt_name, spec, flag)
      end)

    options_section =
      case opt_lines do
        [] -> ["    Options: (none)"]
        lines -> ["    Options:" | lines]
      end

    Enum.join(header ++ options_section, "\n")
  end

  defp format_runtime_opt(opt_name, spec, flag) do
    [
      "      #{opt_name} (#{opt_summary(spec)})",
      "        Flag: #{flag || "(none)"}",
      spec[:doc] && "        #{spec[:doc]}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp opt_summary(spec) do
    parts = [inspect(spec[:type])]
    parts = if Keyword.get(spec, :required, false), do: parts ++ ["required"], else: parts

    parts =
      if Keyword.has_key?(spec, :default),
        do: parts ++ ["default: #{inspect(Keyword.fetch!(spec, :default))}"],
        else: parts

    Enum.join(parts, ", ")
  end

  defp format_kernel_modules(%{kernel_modules: []}), do: "Kernel modules: (none)"

  defp format_kernel_modules(%{kernel_modules: kmods}) do
    "Kernel modules:\n" <> Enum.map_join(kmods, "\n", &"  #{&1}")
  end

  defp format_artifact_sites(%{artifact_sites: []}),
    do: "Artifact sites: (none — source-build only)"

  defp format_artifact_sites(%{artifact_sites: sites}) do
    "Artifact sites:\n" <>
      Enum.map_join(sites, "\n", fn
        {:github_releases, owner_repo} -> "  github_releases: #{owner_repo}"
        {:ghcr, prefix} -> "  ghcr:            #{prefix}"
      end)
  end
end
