defmodule NBPR.Buildroot.Source do
  @moduledoc """
  Manages the cached Buildroot source tree.

  Buildroot is large (~50 MB compressed, ~500 MB extracted) and shared
  across all nbpr operations targeting the same BR version. Layout under
  `$NERVES_DATA_DIR/nbpr/`:

  - `buildroot-dl/` — BR source-tarball cache (shared across BR versions;
    accumulates over time, never invalidated)
  - `buildroot/<version>/` — one extracted, patched, ready-to-use BR tree
    per version, treated as read-only thereafter

  Per-build outputs live elsewhere via BR's `O=<dir>` flag and don't
  contend with this cache.

  Patching is done via the `patch` binary. The patches come from the
  user's `deps/nerves_system_br/patches/buildroot/` and must be applied
  in lexicographic order — Buildroot's own patch script does the same.
  """

  alias NBPR.Artifact.HTTP
  alias NBPR.Buildroot

  @base_url "https://buildroot.org/downloads"

  @doc """
  Returns the absolute path where BR `version` is (or will be) extracted.
  """
  @spec cache_dir(String.t()) :: Path.t()
  def cache_dir(version) when is_binary(version) do
    Path.join([data_dir(), "nbpr", "buildroot", version])
  end

  @doc """
  Returns the shared download cache directory for BR source tarballs.
  """
  @spec download_dir() :: Path.t()
  def download_dir do
    Path.join([data_dir(), "nbpr", "buildroot-dl"])
  end

  @doc """
  Returns `true` when BR `version` is already extracted, patched, and
  marked ready at `cache_dir/1`.
  """
  @spec cached?(String.t()) :: boolean()
  def cached?(version) do
    File.regular?(Path.join(cache_dir(version), ".nbpr-ready"))
  end

  @doc """
  Ensures BR `version` is downloaded, extracted, patched against
  `patches_dir`, and ready at `cache_dir(version)`. Returns the cache path.

  No-op when the version is already cached.
  """
  @spec ensure!(String.t(), Path.t() | nil) :: Path.t()
  def ensure!(version, patches_dir) when is_binary(version) do
    if cached?(version) do
      cache_dir(version)
    else
      do_ensure!(version, patches_dir)
      cache_dir(version)
    end
  end

  @doc false
  @spec apply_patches!(Path.t(), Path.t() | nil) :: :ok
  def apply_patches!(_br_tree, nil), do: :ok

  def apply_patches!(br_tree, patches_dir) when is_binary(patches_dir) do
    Enum.each(Buildroot.patch_files(patches_dir), fn patch ->
      patch_path = Path.join(patches_dir, patch)

      case System.cmd("patch", ["-p1", "-i", patch_path], cd: br_tree, stderr_to_stdout: true) do
        {_, 0} ->
          :ok

        {output, status} ->
          raise "patch #{patch} failed (exit #{status}):\n#{String.trim(output)}"
      end
    end)
  end

  defp do_ensure!(version, patches_dir) do
    HTTP.start_apps!()
    File.mkdir_p!(download_dir())

    tarball = Path.join(download_dir(), "buildroot-#{version}.tar.gz")
    unless File.regular?(tarball), do: download!(version, tarball)

    extract_and_install!(version, tarball, patches_dir)
  end

  defp download!(version, dest_path) do
    url = "#{@base_url}/buildroot-#{version}.tar.gz"

    case :httpc.request(
           :get,
           {String.to_charlist(url), []},
           [autoredirect: true],
           stream: String.to_charlist(dest_path)
         ) do
      {:ok, :saved_to_file} ->
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        _ = File.rm(dest_path)
        raise "BR download failed (HTTP #{status}) from #{url}"

      {:error, reason} ->
        _ = File.rm(dest_path)
        raise "BR download error: #{inspect(reason)}"
    end
  end

  defp extract_and_install!(version, tarball, patches_dir) do
    cache = cache_dir(version)
    staging = make_tmp_dir!()

    try do
      extract_tar!(tarball, staging)

      inner = Path.join(staging, "buildroot-#{version}")

      unless File.dir?(inner) do
        raise "tarball did not contain expected `buildroot-#{version}/` directory"
      end

      apply_patches!(inner, patches_dir)

      File.write!(Path.join(inner, ".nbpr-ready"), version <> "\n")

      File.mkdir_p!(Path.dirname(cache))
      if File.exists?(cache), do: File.rm_rf!(cache)
      File.rename!(inner, cache)
    after
      File.rm_rf!(staging)
    end
  end

  defp extract_tar!(tarball, dest_dir) do
    # Shell out to tar rather than :erl_tar — Buildroot's source tree
    # contains symlinks like `linux/linux.hash -> ../linux/linux.hash` that
    # :erl_tar's security checks (correctly) reject as "unsafe", but they
    # are harmless within BR's own layout. system tar handles them fine.
    case System.cmd("tar", ["-xzf", tarball, "-C", dest_dir], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, status} ->
        raise "BR extract failed (tar exit #{status}): #{String.trim(output)}"
    end
  end

  defp make_tmp_dir! do
    dir = Path.join(System.tmp_dir!(), "nbpr_br_source_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp data_dir do
    cond do
      dir = System.get_env("NERVES_ARTIFACTS_DIR") ->
        dir

      true ->
        base = System.get_env("XDG_DATA_HOME") || Path.join(System.user_home!(), ".local/share")
        Path.join(base, "nerves")
    end
  end
end
