defmodule NBPR.Buildroot.Defconfig do
  @moduledoc """
  Generates a per-build Buildroot defconfig that layers nbpr-specific
  settings on top of the active Nerves system's defconfig.

  Layered on top in order:

  1. The system's defconfig verbatim (e.g. `nerves_system_rpi4/nerves_defconfig`).
  2. `BR2_PER_PACKAGE_DIRECTORIES=y` so per-package builds don't contend.
  3. `BR2_PACKAGE_<UPPER_BR_NAME>=y` to enable the target package.
  4. One line per resolved `build_opt` whose schema declared a `:br_flag`
     extension, formatted as `<br_flag>=<value>` with BR-style boolean,
     string, and integer encoding.

  The result is a defconfig file ready to be loaded with `make defconfig`
  — but typically we'd write it to `O=<dir>/.config` directly and follow
  with `make olddefconfig` to resolve any dependencies.
  """

  @doc """
  Returns the defconfig text for the given inputs as a binary.

  `package` is an `NBPR.Package.t()`. `build_opts` is the resolved keyword
  list (defaults applied) — typically the validated output of
  `NimbleOptions.validate!/2` on the package's `build_opts` schema.
  """
  @spec render!(NBPR.Package.t(), Path.t(), keyword()) :: String.t()
  def render!(%NBPR.Package{} = package, system_defconfig_path, build_opts)
      when is_binary(system_defconfig_path) and is_list(build_opts) do
    base = File.read!(system_defconfig_path)

    nbpr_lines = [
      "# === nbpr additions ===",
      "BR2_PER_PACKAGE_DIRECTORIES=y",
      "BR2_PACKAGE_#{br_symbol(package.br_package)}=y"
    ]

    opt_lines =
      build_opts
      |> Enum.map(&render_build_opt(&1, package))
      |> Enum.reject(&is_nil/1)

    [ensure_trailing_newline(base) | nbpr_lines ++ opt_lines]
    |> Enum.join("\n")
    |> ensure_trailing_newline()
  end

  defp render_build_opt({opt_name, value}, %NBPR.Package{} = package) do
    case get_in(package.build_opt_extensions, [opt_name, :br_flag]) do
      nil -> nil
      br_flag when is_binary(br_flag) -> "#{br_flag}=#{format_br_value(value)}"
    end
  end

  @doc false
  @spec br_symbol(String.t()) :: String.t()
  def br_symbol(br_package) when is_binary(br_package) do
    br_package
    |> String.upcase()
    |> String.replace("-", "_")
    |> String.replace(".", "_")
  end

  @doc false
  @spec format_br_value(term()) :: String.t()
  def format_br_value(true), do: "y"
  def format_br_value(false), do: "n"
  def format_br_value(value) when is_integer(value), do: to_string(value)
  def format_br_value(value) when is_binary(value), do: ~s("#{value}")
  def format_br_value(value) when is_atom(value), do: ~s("#{value}")

  defp ensure_trailing_newline(""), do: ""

  defp ensure_trailing_newline(string) do
    if String.ends_with?(string, "\n"), do: string, else: string <> "\n"
  end
end
