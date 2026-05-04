defmodule NBPR.Buildroot.Package do
  @moduledoc """
  Reads metadata for a Buildroot mainline package from a cached, extracted
  BR tree. Used by `mix nbpr.new` so the scaffolded `mix.exs` and module
  arrive pre-populated with version, licences, homepage, and a starter
  description sourced from BR itself rather than left as `# TODO` stubs.

  ## Inputs

  - `br_tree` — absolute path to an extracted BR tree (typically the one
    cached by `NBPR.Buildroot.Source`).
  - `name` — Buildroot package name as it appears under `package/<name>/`,
    e.g. `"iperf3"`, `"dnsmasq"`, `"kernel-modules"`.

  ## What's read

  | Field         | Source                                                  |
  | ------------- | ------------------------------------------------------- |
  | `version`      | `<NAME>_VERSION` in `<name>.mk`                          |
  | `licences`     | `<NAME>_LICENSE` in `<name>.mk`, comma-split, trimmed    |
  | `homepage`     | First `https?://` URL in `Config.in` help block, else `<NAME>_SITE` |
  | `description`  | First sentence of the `Config.in` help block, capitalised |
  | `title`        | The `bool "..."` label in `Config.in`                    |
  | `help`         | Raw help block (multi-paragraph)                         |
  | `dependencies` | Target-side BR deps: `<NAME>_DEPENDENCIES` ∪ `select BR2_PACKAGE_*` |

  Variable substitution (e.g. `$(<NAME>_VERSION)` references) is *not*
  resolved — this reader takes literal RHS values. Adequate for the common
  case; conditional definitions and computed sites fall back to `nil`.

  ## Dependency extraction

  `dependencies` lists BR package directory names this package needs at
  target-build time. It's the union of:

  - The first literal `<NAME>_DEPENDENCIES = ...` assignment in `<name>.mk`.
    Conditional `_DEPENDENCIES += foo` blocks (gated by `ifeq`/kconfig) are
    deliberately ignored — they depend on user kconfig choices, not on
    intrinsic package wiring, and we have no way to evaluate them
    statically.
  - Every `select BR2_PACKAGE_<X>` line in `Config.in`, lowercased.

  Filtered out:

  - `host-*` deps (build-host tools, never on the target rootfs).
  - `$(...)` make-variable references (can't be resolved without a full BR
    config evaluation; e.g. `$(TARGET_NLS_DEPENDENCIES)`).
  - Duplicates across the two sources.
  """

  defstruct [
    :name,
    :version,
    :licences,
    :homepage,
    :description,
    :title,
    :help,
    dependencies: []
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          licences: [String.t()],
          homepage: String.t() | nil,
          description: String.t() | nil,
          title: String.t() | nil,
          help: String.t() | nil,
          dependencies: [String.t()]
        }

  @doc """
  Reads metadata for `name` from the BR tree at `br_tree`.

  Returns `{:error, :package_not_found}` when `package/<name>/` is absent
  (most likely a misspelt BR package name) and `{:error, :mk_not_found}`
  when the package directory exists but lacks a `<name>.mk` (rare; usually
  a virtual-package umbrella in BR). Missing `_VERSION` or `_LICENSE` keys
  return `{:error, {:missing_var, "<key>"}}`.
  """
  @spec read(Path.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def read(br_tree, name) when is_binary(br_tree) and is_binary(name) do
    pkg_dir = Path.join([br_tree, "package", name])

    if File.dir?(pkg_dir) do
      do_read(pkg_dir, name)
    else
      {:error, :package_not_found}
    end
  end

  defp do_read(pkg_dir, name) do
    mk_path = Path.join(pkg_dir, "#{name}.mk")

    case File.read(mk_path) do
      {:ok, mk_content} -> from_mk(pkg_dir, name, mk_content)
      {:error, :enoent} -> {:error, :mk_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp from_mk(pkg_dir, name, mk_content) do
    var_prefix = var_prefix(name)

    with {:ok, version} <- extract_var(mk_content, var_prefix, "VERSION"),
         {:ok, licence_str} <- extract_var(mk_content, var_prefix, "LICENSE") do
      site = mk_content |> extract_var(var_prefix, "SITE") |> ok_value()

      config_in =
        case File.read(Path.join(pkg_dir, "Config.in")) do
          {:ok, content} -> content
          _ -> nil
        end

      {title, help} =
        case config_in do
          nil -> {nil, nil}
          content -> parse_config_in(content, var_prefix)
        end

      {:ok,
       %__MODULE__{
         name: name,
         version: version,
         licences: split_licences(licence_str),
         homepage: extract_homepage(help) || site,
         description: derive_description(help),
         title: title,
         help: help,
         dependencies: extract_dependencies(mk_content, config_in, var_prefix)
       }}
    end
  end

  defp extract_dependencies(mk_content, config_in, var_prefix) do
    mk_deps = extract_mk_dependencies(mk_content, var_prefix)
    select_deps = extract_config_selects(config_in)

    (mk_deps ++ select_deps)
    |> Enum.reject(&host_dep?/1)
    |> Enum.reject(&make_var_ref?/1)
    |> Enum.uniq()
  end

  defp extract_mk_dependencies(content, prefix) do
    case Regex.run(~r/^#{prefix}_DEPENDENCIES\s*=\s*(.*)$/m, content) do
      [_, line] -> String.split(line, ~r/\s+/, trim: true)
      _ -> []
    end
  end

  defp extract_config_selects(nil), do: []

  defp extract_config_selects(content) do
    ~r/^\s*select\s+BR2_PACKAGE_([A-Z0-9_]+)/m
    |> Regex.scan(content)
    |> Enum.map(fn [_, kconfig] -> String.downcase(kconfig) end)
  end

  defp host_dep?(name), do: String.starts_with?(name, "host-")

  defp make_var_ref?(name), do: String.contains?(name, "$")

  defp var_prefix(name), do: name |> String.upcase() |> String.replace("-", "_")

  defp extract_var(content, prefix, suffix) do
    re = Regex.compile!("^#{Regex.escape(prefix)}_#{suffix}\\s*=\\s*(.*)$", "m")

    case Regex.run(re, content) do
      [_, value] -> {:ok, String.trim(value)}
      _ -> {:error, {:missing_var, "#{prefix}_#{suffix}"}}
    end
  end

  defp split_licences(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_config_in(content, var_prefix) do
    marker = "config BR2_PACKAGE_#{var_prefix}"

    case String.split(content, marker, parts: 2) do
      [_, after_marker] -> {extract_title(after_marker), extract_help(after_marker)}
      _ -> {nil, nil}
    end
  end

  defp extract_title(after_marker) do
    case Regex.run(~r/^\s*bool\s+"([^"]+)"/m, after_marker) do
      [_, t] -> t
      _ -> nil
    end
  end

  # BR help blocks open with a `help` line, then indented (TAB or spaces)
  # body lines. Blank lines are paragraph breaks within the block. The
  # block terminates at the first non-blank, non-indented line.
  defp extract_help(after_marker) do
    lines = String.split(after_marker, "\n")

    case Enum.find_index(lines, &Regex.match?(~r/^\s*help\s*$/, &1)) do
      nil ->
        nil

      i ->
        body =
          lines
          |> Enum.drop(i + 1)
          |> Enum.take_while(fn line -> line == "" or String.match?(line, ~r/^[ \t]/) end)
          |> Enum.map(&String.trim_leading/1)
          |> Enum.join("\n")
          |> String.trim()

        if body == "", do: nil, else: body
    end
  end

  defp extract_homepage(nil), do: nil

  defp extract_homepage(help) do
    case Regex.run(~r{https?://\S+}, help) do
      [url] -> url |> String.trim_trailing(",") |> String.trim_trailing(".")
      _ -> nil
    end
  end

  defp derive_description(nil), do: nil

  defp derive_description(help) do
    first_para =
      help
      |> String.split(~r/\n\s*\n/)
      |> List.first()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    first_para
    |> String.split(~r/(?<=[.!?])\s+/, parts: 2)
    |> List.first()
    |> capitalise_first()
  end

  defp capitalise_first(""), do: ""

  defp capitalise_first(<<first::utf8, rest::binary>>) do
    <<String.upcase(<<first::utf8>>)::binary, rest::binary>>
  end

  defp ok_value({:ok, v}), do: v
  defp ok_value(_), do: nil
end
