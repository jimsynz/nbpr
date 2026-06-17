defmodule NBPR.Artifact.Cache do
  @moduledoc """
  On-disk cache for NBPR package artefacts.

  Pure path/key logic lives in `NBPR.Artifact`; this module owns the I/O —
  checking whether an artefact is already extracted, and atomically extracting
  a downloaded tarball into the cache directory.

  Extraction goes via a sibling temp directory and then a rename, so a failed
  extract never leaves a half-populated cache directory behind.
  """

  alias NBPR.Artifact

  @type entry :: %{
          dir: String.t(),
          path: String.t(),
          manifest: map() | nil,
          mtime: integer()
        }

  @doc """
  Returns `true` when the artefact is already extracted into the cache
  directory. Currently a presence check; manifest-based verification is added
  alongside the resolver in a later commit.
  """
  @spec valid?(Artifact.build_inputs()) :: boolean()
  def valid?(%{} = inputs) do
    File.dir?(Artifact.cache_dir(inputs))
  end

  @doc """
  Lists extracted artefacts in the cache root.

  An entry is a cache-root subdirectory containing a `manifest.json` — this
  skips siblings like `dl/` (staged downloads) and `system-source/`. Each
  entry carries its directory name, absolute path, parsed manifest (or `nil`
  if the JSON is unreadable), and POSIX mtime. Sorted newest-first.
  """
  @spec list() :: [entry()]
  def list do
    root = Artifact.cache_root()

    case File.ls(root) do
      {:ok, names} ->
        names
        |> Enum.map(&Path.join(root, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.filter(&File.regular?(Path.join(&1, "manifest.json")))
        |> Enum.map(&describe_entry/1)
        |> Enum.sort_by(& &1.mtime, :desc)

      {:error, _} ->
        []
    end
  end

  @doc """
  Removes a single cache entry by absolute path. Returns `:ok`.
  """
  @spec remove!(Path.t()) :: :ok
  def remove!(path) do
    File.rm_rf!(path)
    :ok
  end

  defp describe_entry(path) do
    %{
      dir: Path.basename(path),
      path: path,
      manifest: read_manifest(path),
      mtime: mtime(path)
    }
  end

  defp read_manifest(path) do
    case File.read(Path.join(path, "manifest.json")) do
      {:ok, contents} -> :json.decode(contents)
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime
      {:error, _} -> 0
    end
  end

  @doc """
  Extracts a downloaded tarball into the canonical cache directory for the
  given inputs.

  The tarball is expected to contain exactly one top-level directory (matching
  Nerves' `--strip-components=1` convention); the contents of that directory
  become the cache directory's contents. Extraction is atomic via a temp
  directory + rename.
  """
  @spec extract!(Path.t(), Artifact.build_inputs()) :: :ok
  def extract!(tarball_path, %{} = inputs) do
    cache_dir = Artifact.cache_dir(inputs)
    tmp_dir = staging_dir(cache_dir)

    File.mkdir_p!(tmp_dir)

    try do
      extract_tarball!(tarball_path, tmp_dir)
      install!(tmp_dir, cache_dir)
      :ok
    after
      File.rm_rf!(tmp_dir)
    end
  end

  defp extract_tarball!(tarball_path, dest_dir) do
    # Shell out to system tar — `:erl_tar` rejects cross-directory relative
    # symlinks (e.g. `target/usr/lib/libfoo.so` → `../../lib/libfoo.so.1`),
    # which are legitimate and common in Buildroot artefacts (util-linux,
    # mesa3d, multi-prefix libraries generally).
    case System.cmd("tar", ["-xzf", tarball_path, "-C", dest_dir], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, code} ->
        raise "failed to extract #{tarball_path} (tar exit #{code}): #{output}"
    end
  end

  defp install!(tmp_dir, cache_dir) do
    case File.ls!(tmp_dir) do
      [single] ->
        inner = Path.join(tmp_dir, single)

        unless File.dir?(inner) do
          raise "tarball must contain a single top-level directory; found a file named #{single}"
        end

        File.mkdir_p!(Path.dirname(cache_dir))
        if File.exists?(cache_dir), do: File.rm_rf!(cache_dir)
        File.rename!(inner, cache_dir)

      [] ->
        raise "tarball is empty"

      others ->
        raise "tarball must contain a single top-level directory; found #{length(others)} entries"
    end
  end

  # Stage as a sibling of the destination, not under `System.tmp_dir!/0`: the
  # final step is a rename into the cache dir, and an atomic rename only works
  # within one filesystem. `/tmp` is frequently a separate mount (tmpfs) from
  # the user's data dir, which would make the rename fail with `:exdev`
  # (cross-device).
  @doc false
  @spec staging_dir(Path.t()) :: Path.t()
  def staging_dir(cache_dir) do
    Path.join(Path.dirname(cache_dir), ".extract-#{System.unique_integer([:positive])}")
  end
end
