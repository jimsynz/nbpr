defmodule NBPR.Linux.Defconfig do
  @moduledoc """
  Renders the Buildroot defconfig for a kernel rebuild: the active system's
  `nerves_defconfig` verbatim, plus authoritative `BR2_LINUX_KERNEL_*` lines
  that layer in the user's config fragments and patches.

  The kernel version is **not** touched — by reusing the system's defconfig and
  leaving `BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION` alone, the rebuild pins to
  exactly the source the system already uses (a vendor fork tag for rpi, mainline
  + patches for bbb, etc.).

  ## Merge, don't clobber

  `BR2_LINUX_KERNEL_PATCH` and `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` are
  space-separated lists. Some systems already set them (e.g. bbb's TI kernel
  patches). A bare appended line would win under `make olddefconfig` and silently
  drop the system's own value, so we read the existing value out of the base
  defconfig and emit a single merged line that includes both.
  """

  @fragment_var "BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES"
  @patch_var "BR2_LINUX_KERNEL_PATCH"

  @doc """
  Returns the defconfig text. `fragment_paths` and `patch_paths` are absolute
  paths visible to the Buildroot invocation (Buildroot reads them at build time).
  """
  @spec render(String.t(), [Path.t()], [Path.t()]) :: String.t()
  def render(base, fragment_paths, patch_paths)
      when is_binary(base) and is_list(fragment_paths) and is_list(patch_paths) do
    lines =
      [
        merged_line(base, @fragment_var, fragment_paths),
        merged_line(base, @patch_var, patch_paths)
      ]
      |> Enum.reject(&is_nil/1)

    case lines do
      [] ->
        ensure_trailing_newline(base)

      lines ->
        ensure_trailing_newline(base) <>
          "# === nbpr_linux ===\n" <> Enum.join(lines, "\n") <> "\n"
    end
  end

  defp merged_line(_base, _var, []), do: nil

  defp merged_line(base, var, paths) do
    merged = (existing_values(base, var) ++ paths) |> Enum.uniq()
    ~s(#{var}="#{Enum.join(merged, " ")}")
  end

  @doc false
  @spec existing_values(String.t(), String.t()) :: [String.t()]
  def existing_values(base, var) do
    case Regex.run(~r/^#{Regex.escape(var)}="([^"]*)"/m, base) do
      [_, value] -> value |> String.split(" ", trim: true)
      _ -> []
    end
  end

  defp ensure_trailing_newline(string) do
    if String.ends_with?(string, "\n"), do: string, else: string <> "\n"
  end
end
