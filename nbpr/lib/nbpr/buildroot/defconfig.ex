defmodule NBPR.Buildroot.Defconfig do
  @moduledoc """
  Generates a per-build Buildroot defconfig that layers nbpr-specific
  settings on top of the active Nerves system's defconfig.

  Layered on top in order:

  1. The system's defconfig verbatim (e.g. `nerves_system_rpi4/nerves_defconfig`).
  2. `BR2_PER_PACKAGE_DIRECTORIES=y` so per-package builds don't contend.
  3. `BR2_PACKAGE_BUSYBOX_SHOW_OTHERS=y` so packages overlapping busybox
     applets (e.g. kmod's tools) aren't dropped as unmet dependencies.
  4. `BR2_PRIMARY_SITE` pointing at Buildroot's source archive — see below.
  5. One line per kconfig symbol gating a nested package — see below.
  6. `BR2_PACKAGE_<UPPER_BR_NAME>=y` to enable the target package.
  7. One line per resolved `build_opt` whose schema declared a `:br_flag`
     extension, formatted as `<br_flag>=<value>` with BR-style boolean,
     string, and integer encoding. A `:br_flag` naming a list of symbols
     emits one line each, all carrying the same value — which is what
     Buildroot's virtual packages need, where enabling a feature means
     setting both the virtual symbol and a provider from the `choice`
     beneath it.

  The result is a defconfig file ready to be loaded with `make defconfig`
  — but typically we'd write it to `O=<dir>/.config` directly and follow
  with `make olddefconfig` to resolve any dependencies.

  ## Nested packages and their gating symbols

  Most Buildroot packages live at `package/<name>/`, and `BR2_PACKAGE_<NAME>=y`
  is all it takes to select one. Some live one level deeper, at
  `package/<parent>/<name>/`, and their `Config.in` is sourced from the
  parent's inside an `if` block — `fftw-single` under `fftw`, every `xlib_*`
  and `xdriver_*` under `x11r7`, the `qt5*`/`qt6*` and `gst1-*` families.

  For those, `BR2_PACKAGE_<NAME>=y` on its own is *silently discarded* by
  `make olddefconfig`: the symbol's dependencies aren't met, so kconfig drops
  it, the package never builds, and the failure only surfaces later as a
  missing per-package output directory.

  The gating symbols can't be derived from the parent directory's name —
  `package/x11r7/` is gated by `BR2_PACKAGE_XORG7`, not `BR2_PACKAGE_X11R7`,
  and `package/opengl/` sources its children with no gate at all. Nor can the
  directory be trusted to hold the declaration: `package/jpeg-turbo/` ships
  only a `.mk` and a `Config.in.options`, while `BR2_PACKAGE_JPEG_TURBO`
  itself is declared inside the `choice` in `package/jpeg/Config.in`, under
  `if BR2_PACKAGE_JPEG`.

  So the gates are read from the tree, starting from wherever the symbol is
  actually declared:

  1. the `if` blocks wrapping the `config` stanza in its own file, then
  2. the `if` blocks wrapping each `source` line on the chain from that file
     up to `package/Config.in`.

  Outermost first. Both halves are real: the modular Xorg drivers sit inside
  `if BR2_PACKAGE_XORG7` *and* `if BR2_PACKAGE_XSERVER_XORG_SERVER_MODULAR`
  by inclusion, while `jpeg-turbo` is gated by its declaring stanza alone.
  `choice`/`endchoice` is not a gate — it groups alternatives, and setting a
  member to `y` is how you pick one.

  Only bare symbol conditions are emitted. A compound condition (Buildroot
  has one, an `||` over two `freescale-imx` platform choices) is a choice
  between alternatives that nbpr has no basis to make, so it's left alone.

  Top-level packages are deliberately excluded from this lookup even though
  `package/Config.in` has `if` blocks of its own: they already build, and
  re-deriving their gates would change what every existing package's build
  sees for no benefit.

  ## Why the primary site is set

  `BR2_BACKUP_SITE` defaults to Buildroot's own source archive, which mirrors
  every tarball mainline Buildroot references. Nerves systems override it to
  `https://dl.nerves-project.org`, which only carries what a Nerves system
  itself builds — reasonable for them, useless here, because nbpr's whole
  purpose is building packages Nerves systems *don't* include.

  Left alone, an nbpr build's only real source is the package's own upstream
  site, and some of those are unreliable: gpsd's is a Savannah mirror over
  plain HTTP, which times out often enough from CI runners to fail roughly half
  a nine-target matrix, with `dl.nerves-project.org` then returning 403.

  Setting `BR2_PRIMARY_SITE` to the archive fixes that without touching the
  system's backup choice. Buildroot tries the primary site *first* and falls
  back to the package's own site, so downloads get faster and more reliable at
  the same time, and upstreams see less traffic — which is what Buildroot
  recommends the option for.
  """

  # Buildroot's own source archive: every tarball mainline BR references,
  # under `<pkg>/<filename>`.
  @primary_site "https://sources.buildroot.net"

  @doc """
  Returns the defconfig text for the given inputs as a binary.

  `package` is an `NBPR.Package.t()`. `br_tree` is an extracted Buildroot
  source tree (from `NBPR.Buildroot.Source.ensure!/2`), read to derive the
  gating symbols of a nested package. `build_opts` is the resolved keyword
  list (defaults applied) — typically the validated output of
  `NimbleOptions.validate!/2` on the package's `build_opts` schema.
  """
  @spec render!(NBPR.Package.t(), Path.t(), Path.t(), keyword()) :: String.t()
  def render!(%NBPR.Package{} = package, system_defconfig_path, br_tree, build_opts)
      when is_binary(system_defconfig_path) and is_binary(br_tree) and is_list(build_opts) do
    base = File.read!(system_defconfig_path)

    # SHOW_OTHERS only unhides BR packages that overlap busybox applets
    # (e.g. kmod's tools); without it `make olddefconfig` silently drops
    # them as unmet dependencies. It doesn't change busybox itself.
    nbpr_lines =
      [
        "# === nbpr additions ===",
        "BR2_PER_PACKAGE_DIRECTORIES=y",
        "BR2_PACKAGE_BUSYBOX_SHOW_OTHERS=y",
        ~s(BR2_PRIMARY_SITE="#{@primary_site}")
      ] ++
        Enum.map(gating_symbols(br_tree, package.br_package), &"#{&1}=y") ++
        ["BR2_PACKAGE_#{br_symbol(package.br_package)}=y"]

    opt_lines = Enum.flat_map(build_opts, &render_build_opt(&1, package))

    [ensure_trailing_newline(base) | nbpr_lines ++ opt_lines]
    |> Enum.join("\n")
    |> ensure_trailing_newline()
  end

  @doc """
  Returns the kconfig symbols that must be `y` for `br_package` to be
  selectable, outermost first.

  Empty for a package whose symbol is declared at the top level of its own
  `Config.in` and sourced unconditionally.
  """
  @spec gating_symbols(Path.t(), String.t()) :: [String.t()]
  def gating_symbols(br_tree, br_package) when is_binary(br_tree) and is_binary(br_package) do
    symbol = "BR2_PACKAGE_" <> br_symbol(br_package)

    case declaring_config(br_tree, br_package, symbol) do
      nil -> []
      config -> declaration_symbols(config, symbol) ++ source_chain_symbols(config, br_tree)
    end
  end

  # A package's symbol usually lives in its own directory's `Config.in`, but
  # not always: `package/jpeg-turbo/` ships only a `.mk` and
  # `Config.in.options`, with `BR2_PACKAGE_JPEG_TURBO` declared inside the
  # `choice` in `package/jpeg/Config.in`. So the directory is a hint, not the
  # answer — fall back to whichever `Config.in` actually declares the symbol.
  defp declaring_config(br_tree, br_package, symbol) do
    own = Path.join([br_tree, "package", br_package, "Config.in"])
    nested = Path.join([br_tree, "package", "*", br_package, "Config.in"])

    ([own] ++
       Path.wildcard(nested) ++ Path.wildcard(Path.join([br_tree, "package", "*", "Config.in"])))
    |> Enum.find(&declares?(&1, symbol))
  end

  defp declares?(config, symbol) do
    case File.read(config) do
      {:ok, contents} -> Regex.match?(~r/^\s*config\s+#{Regex.escape(symbol)}\s*$/m, contents)
      {:error, _} -> false
    end
  end

  # The `if` blocks wrapping the `config` stanza inside its own file.
  # `choice`/`endchoice` are ignored: they group alternatives without gating
  # them, and setting a member to `y` is how you pick one.
  defp declaration_symbols(config, symbol) do
    scan_to(config, ~r/^\s*config\s+#{Regex.escape(symbol)}\s*$/)
  end

  # Walks up the `source` chain from `config` to `package/Config.in`,
  # collecting the `if` blocks wrapping each inclusion. Top-level packages
  # stop here by construction: `package/Config.in` has `if` blocks of its own,
  # but those already build, and re-deriving their gates would change what
  # every existing package's build sees for no benefit.
  defp source_chain_symbols(config, br_tree) do
    parent = config |> Path.dirname() |> Path.dirname() |> Path.join("Config.in")
    top_level = Path.join([br_tree, "package", "Config.in"])

    if parent == top_level or not File.regular?(parent) do
      []
    else
      source_line = ~s(source "#{Path.relative_to(config, br_tree)}")
      gates = scan_to(parent, ~r/^\s*#{Regex.escape(source_line)}\s*$/)

      source_chain_symbols(parent, br_tree) ++ gates
    end
  end

  defp scan_to(config, target) do
    case File.read(config) do
      {:ok, contents} -> contents |> String.split("\n") |> scan_for_target(target, [])
      {:error, _} -> []
    end
  end

  # Walks a `Config.in` tracking the `if`/`endif` nesting, and stops at the
  # first line matching `target`. Anything but a bare symbol is dropped: a
  # compound condition isn't something we can satisfy by setting one line.
  defp scan_for_target([], _target, _stack), do: []

  defp scan_for_target([line | rest], target, stack) do
    cond do
      Regex.match?(target, line) ->
        stack |> Enum.reverse() |> Enum.filter(&bare_symbol?/1)

      condition = if_condition(line) ->
        scan_for_target(rest, target, [condition | stack])

      endif?(line) ->
        scan_for_target(rest, target, Enum.drop(stack, 1))

      true ->
        scan_for_target(rest, target, stack)
    end
  end

  defp if_condition(line) do
    case Regex.run(~r/^\s*if\s+(\S.*?)\s*$/, line) do
      [_, condition] -> condition
      _ -> nil
    end
  end

  defp endif?(line), do: Regex.match?(~r/^\s*endif\b/, line)

  defp bare_symbol?(condition), do: Regex.match?(~r/^BR2_[A-Z0-9_]+$/, condition)

  # A `:br_flag` may name several symbols. Buildroot's virtual packages need
  # it: turning on JPEG means `BR2_PACKAGE_JPEG=y` *and* a provider from the
  # `choice` under it, and leaving the provider to kconfig's default picks a
  # different one per target.
  defp render_build_opt({opt_name, value}, %NBPR.Package{} = package) do
    package.build_opt_extensions
    |> get_in([opt_name, :br_flag])
    |> List.wrap()
    |> Enum.map(&"#{&1}=#{format_br_value(value)}")
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
