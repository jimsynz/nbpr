defmodule NBPR.Buildroot.FilesList do
  @moduledoc """
  Reads Buildroot's per-package `.files-list.txt` / `.files-list-staging.txt`
  and copies only the listed files (with a runtime-only filter) out of a
  per-package merged sysroot.

  ## Why

  In `BR2_PER_PACKAGE_DIRECTORIES=y` mode, `<O>/per-package/<pkg>/target/` is
  the merged result of the BR target skeleton, every transitive dep, AND the
  package itself — copying it wholesale ships ~36MB of toolchain libs
  (`libc.so.6`, `libstdc++.so.6`, ...) plus skeleton config (`/etc/passwd`,
  `THIS_IS_NOT_YOUR_ROOT_FILESYSTEM`, ...) in every artefact.

  Buildroot writes a per-package files-list to the package's build dir during
  `make <pkg>` (NOT `<pkg>-rebuild` — that skips the before-snapshot, leaving
  the lists empty). Each line is `<pkg>,./<path>` relative to `target/` (or
  `staging/`).

  ## Runtime filter

  Even within the package's own contribution, NBPR artefacts are runtime-only
  — dev/docs paths are dropped:

    - `usr/include/**` (headers)
    - `usr/lib/pkgconfig/**` (pkg-config)
    - `usr/share/{doc,man,info}/**` (docs, manpages)
    - `*.la` (libtool archives)
  """

  @doc """
  Reads `files_list_path` and copies each listed file from `src_root` to
  `dst_root`, preserving the relative path layout, attributes, and symlinks.

  Skips dev/docs paths. Missing source files are silently skipped (BR's
  files-list can include staging-only entries that don't exist in target/).

  Creates `dst_root` and any needed intermediate directories. Returns `:ok`.
  Raises only on actual filesystem errors during copy.

  When the files-list doesn't exist, returns `:ok` without copying anything
  — caller decides whether that's an error.
  """
  @spec copy!(Path.t(), Path.t(), Path.t(), keyword()) :: :ok
  def copy!(src_root, dst_root, files_list_path, opts \\ [])
      when is_binary(src_root) and is_binary(dst_root) and is_binary(files_list_path) do
    keep_dev = Keyword.get(opts, :keep_dev, false)

    if File.regular?(files_list_path) do
      File.mkdir_p!(dst_root)

      files_list_path
      |> File.stream!()
      |> Stream.map(&parse_line/1)
      |> Stream.reject(&is_nil/1)
      |> Stream.reject(&filter_out?(&1, keep_dev))
      |> Enum.each(&copy_one!(src_root, dst_root, &1))
    end

    :ok
  end

  defp parse_line(line) do
    case String.trim_trailing(line) do
      "" ->
        nil

      stripped ->
        case String.split(stripped, ",", parts: 2) do
          [_pkg, "./" <> rel] -> rel
          [_pkg, rel] -> rel
          _ -> nil
        end
    end
  end

  # `keep_dev: true` (the staging tree) retains headers, pkg-config, and CMake
  # config files so a consumer NIF can cross-compile against a shipped library.
  # Docs/manpages and libtool archives are dropped either way.
  defp filter_out?(rel, true), do: doc_path?(rel)
  defp filter_out?(rel, false), do: dev_path?(rel) or doc_path?(rel)

  defp dev_path?(rel) do
    String.starts_with?(rel, "usr/include/") or
      String.starts_with?(rel, "usr/lib/pkgconfig/")
  end

  defp doc_path?(rel) do
    String.starts_with?(rel, "usr/share/doc/") or
      String.starts_with?(rel, "usr/share/man/") or
      String.starts_with?(rel, "usr/share/info/") or
      String.ends_with?(rel, ".la")
  end

  defp copy_one!(src_root, dst_root, rel) do
    src = Path.join(src_root, rel)
    dst = Path.join(dst_root, rel)

    case File.lstat(src) do
      {:ok, %File.Stat{type: :symlink}} ->
        File.mkdir_p!(Path.dirname(dst))
        {:ok, target} = File.read_link(src)
        _ = File.rm(dst)
        File.ln_s!(target, dst)

      {:ok, %File.Stat{type: :regular}} ->
        File.mkdir_p!(Path.dirname(dst))
        File.cp!(src, dst)

      {:ok, %File.Stat{}} ->
        :ok

      {:error, :enoent} ->
        :ok
    end
  end
end
