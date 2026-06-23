defmodule NBPR.Sysroot do
  @moduledoc """
  Overlays nbpr package `staging/` (headers, `*.pc`, `*.so`) onto the Nerves
  build sysroot so a project's NIF cross-compiles can resolve them via
  `pkg-config` / `#include` — without mutating the shared system artefact.

  Used by `mix nbpr.stage`. It builds a shadow `NERVES_SYSTEM`: a symlink farm
  of the real system whose `staging/` is a hardlinked mirror with the package
  staging files injected on top (instant, ~no disk on one filesystem).
  `--remove-destination` guarantees an injected file unlinks the shadow's
  hardlink first, so the shared real-staging inode is never written through.
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
    mirror!(Path.join(system_path, "staging"), shadow_staging)
    Enum.each(staging_dirs, &overlay!(&1, shadow_staging))
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

  # Hardlink-mirror when on a single filesystem; fall back to a full copy.
  defp mirror!(src, dst) do
    case System.cmd("cp", ["-al", src, dst], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> {_out, 0} = System.cmd("cp", ["-a", src, dst])
    end
  end

  defp overlay!(src, dst) do
    {_out, 0} = System.cmd("cp", ["-a", "--remove-destination", src <> "/.", dst <> "/"])
  end
end
