defmodule NBPR.Sysroot do
  @moduledoc """
  Overlays nbpr package `staging/` (headers, `*.pc`, `*.so`) onto the Nerves
  build sysroot so a project's NIF cross-compiles can resolve them via
  `pkg-config` / `#include` — without mutating the shared system artefact.

  Used by `mix nbpr.stage`. It builds a shadow `NERVES_SYSTEM`: a symlink farm
  of the real system whose `staging/` is a **hardlinked** mirror of the real
  staging with the package staging files copied on top. Hardlinking the mirror
  is instant and uses ~no extra disk on a single filesystem (the staging sysroot
  is large and gets rebuilt every `mix firmware`); a copy would duplicate the
  whole sysroot each time.

  Each overlaid file is `rm`'d before it's written, so the copy unlinks the
  mirror's hardlink rather than writing through it — the shared real-staging
  inode is never touched.

  This is deliberately separate from `NBPR.Linux.Shadow`: that one overrides a
  handful of flat files in `images/` with symlinks, whereas this mirrors a large
  tree and overlays a small one. The materialisation strategies don't share
  enough to justify a common abstraction.
  """

  @doc """
  Builds a shadow system at `shadow` mirroring `system_path`, with the package
  `staging_dirs` overlaid onto its `staging/`. Returns the shadow's `staging`
  path (the new sysroot).
  """
  @spec system_shadow!(Path.t(), [Path.t()], Path.t()) :: Path.t()
  def system_shadow!(system_path, staging_dirs, shadow)
      when is_binary(system_path) and is_list(staging_dirs) and is_binary(shadow) do
    File.rm_rf!(shadow)
    File.mkdir_p!(shadow)

    for name <- File.ls!(system_path), name != "staging" do
      File.ln_s!(Path.join(system_path, name), Path.join(shadow, name))
    end

    shadow_staging = Path.join(shadow, "staging")
    clone_tree!(Path.join(system_path, "staging"), shadow_staging, &hardlink!/2)
    Enum.each(staging_dirs, fn dir -> clone_tree!(dir, shadow_staging, &copy!/2) end)
    shadow_staging
  end

  @doc """
  Repoints every environment variable that references `real` at `shadow` (the
  `--sysroot` baked into `CFLAGS`/`LDFLAGS`, `PKG_CONFIG_SYSROOT_DIR`,
  `NERVES_SDK_SYSROOT`, ...). A no-op for the vars that don't mention it. Covers
  the case where the Nerves env was already bootstrapped against the real
  staging before staging ran.
  """
  @spec repoint_env!(Path.t(), Path.t()) :: :ok
  def repoint_env!(real, shadow) when is_binary(real) and is_binary(shadow) do
    Enum.each(System.get_env(), fn {k, v} ->
      if is_binary(v) and String.contains?(v, real) do
        System.put_env(k, String.replace(v, real, shadow))
      end
    end)
  end

  # Walks `src` and reproduces it under `dst`: directories are recreated,
  # symlinks recreated verbatim, and regular files handed to `file_action`
  # (hardlink for the mirror, copy for the overlay). `dst` may already exist
  # (the overlay lands on top of the mirror), so every leaf is unlinked first.
  defp clone_tree!(src, dst, file_action) do
    File.mkdir_p!(dst)

    Enum.each(File.ls!(src), fn name ->
      source = Path.join(src, name)
      dest = Path.join(dst, name)

      case File.lstat!(source).type do
        :directory -> clone_tree!(source, dest, file_action)
        :symlink -> relink!(source, dest)
        _ -> file_action.(source, dest)
      end
    end)
  end

  defp relink!(source, dest) do
    File.rm_rf!(dest)
    {:ok, target} = File.read_link(source)
    File.ln_s!(target, dest)
  end

  defp hardlink!(source, dest) do
    File.rm_rf!(dest)

    case File.ln(source, dest) do
      :ok -> :ok
      {:error, _cross_device} -> File.cp!(source, dest)
    end
  end

  defp copy!(source, dest) do
    File.rm_rf!(dest)
    File.cp!(source, dest)
  end
end
