defmodule NBPR.Linux.Shadow do
  @moduledoc """
  Builds a shadow `NERVES_SYSTEM` directory: a symlink farm mirroring the real
  Nerves system artefact, but with the kernel image and device trees in
  `images/` replaced by an nbpr_linux build's `boot/` files.

  `fwup` reads the kernel from `${NERVES_SYSTEM}/images/...` by absolute path,
  so the only way to swap the kernel without a rootfs overlay is to point
  `NERVES_SYSTEM` at a directory whose `images/` holds the replacement. The rest
  of the system (scripts, staging, fwup.conf, rpi-firmware, the base
  `rootfs.squashfs`) is symlinked straight back to the real artefact, so the
  shared artefact cache is never mutated.
  """

  @doc """
  (Re)builds the shadow system dir at `shadow_path` from `system_path`,
  overriding `images/` entries with the files in `boot_dir`. Returns
  `shadow_path`.
  """
  @spec build!(Path.t(), Path.t(), Path.t()) :: Path.t()
  def build!(system_path, boot_dir, shadow_path)
      when is_binary(system_path) and is_binary(boot_dir) and is_binary(shadow_path) do
    File.rm_rf!(shadow_path)
    File.mkdir_p!(shadow_path)

    link_children(system_path, shadow_path, except: ["images"])

    shadow_images = Path.join(shadow_path, "images")
    File.mkdir_p!(shadow_images)
    link_children(Path.join(system_path, "images"), shadow_images, except: [])

    Enum.each(list_files(boot_dir), fn override ->
      link = Path.join(shadow_images, Path.basename(override))
      File.rm_rf!(link)
      File.ln_s!(override, link)
    end)

    shadow_path
  end

  defp link_children(src_dir, dest_dir, except: except) do
    src_dir
    |> File.ls!()
    |> Enum.reject(&(&1 in except))
    |> Enum.each(fn name ->
      File.ln_s!(Path.join(src_dir, name), Path.join(dest_dir, name))
    end)
  end

  defp list_files(dir) do
    if File.dir?(dir) do
      dir |> File.ls!() |> Enum.map(&Path.join(dir, &1)) |> Enum.filter(&File.regular?/1)
    else
      []
    end
  end
end
