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
    tmp_dir = staging_dir()

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
    case :erl_tar.extract(
           String.to_charlist(tarball_path),
           [:compressed, {:cwd, String.to_charlist(dest_dir)}]
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "failed to extract #{tarball_path}: #{inspect(reason)}"
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

  defp staging_dir do
    Path.join(System.tmp_dir!(), "nbpr_extract_#{System.unique_integer([:positive])}")
  end
end
