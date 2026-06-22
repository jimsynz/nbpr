defmodule NBPR.Linux.Harvest do
  @moduledoc """
  Collects the outputs of a `make linux` build into the source directories
  `NBPR.Pack` expects:

  - `boot/` — the kernel image and device trees from `<output>/images/`.
    These can't ride a rootfs overlay; at install time they replace the
    corresponding files in a shadow `NERVES_SYSTEM/images/` (see
    `NBPR.Linux.Shadow`), which is what `fwup` reads the kernel from.
  - `rootfs/lib/modules/<version>/` — the in-tree modules from
    `<output>/target/lib/modules/`, which DO ride the standard rootfs overlay.

  The build runs in a dedicated output dir that only ever runs `make linux`,
  so `images/` holds exactly the kernel's outputs — no full-system cruft.
  """

  # Buildroot installs the kernel under one of these names depending on arch.
  @kernel_image_names ~w(Image Image.gz zImage uImage bzImage xipImage vmlinux vmlinuz)

  @doc """
  Populates `dest_root/boot` and `dest_root/rootfs` from the Buildroot
  `output_dir`, and returns the `NBPR.Pack.sources()` map pointing at them.

  Raises if no kernel image is found — a sign `make linux` didn't run.
  """
  @spec collect!(Path.t(), Path.t()) :: NBPR.Pack.sources()
  def collect!(output_dir, dest_root) when is_binary(output_dir) and is_binary(dest_root) do
    images = Path.join(output_dir, "images")
    kernel_images = kernel_image_files(images)

    if kernel_images == [] do
      raise """
      no kernel image found in #{images}.

      Expected one of #{Enum.join(@kernel_image_names, ", ")} after `make linux`.
      """
    end

    boot_dest = Path.join(dest_root, "boot")
    File.mkdir_p!(boot_dest)

    Enum.each(kernel_images ++ device_tree_files(images), fn src ->
      File.cp!(src, Path.join(boot_dest, Path.basename(src)))
    end)

    sources = %{boot: boot_dest}

    case collect_modules!(output_dir, dest_root) do
      nil -> sources
      rootfs_dest -> Map.put(sources, :rootfs, rootfs_dest)
    end
  end

  defp kernel_image_files(images) do
    for name <- @kernel_image_names,
        path = Path.join(images, name),
        File.regular?(path),
        do: path
  end

  defp device_tree_files(images) do
    Path.wildcard(Path.join(images, "*.dtb")) ++ Path.wildcard(Path.join(images, "*.dtbo"))
  end

  defp collect_modules!(output_dir, dest_root) do
    modules_src = Path.join([output_dir, "target", "lib", "modules"])

    if File.dir?(modules_src) and File.ls!(modules_src) != [] do
      lib_dest = Path.join([dest_root, "rootfs", "lib"])
      File.mkdir_p!(lib_dest)
      File.cp_r!(modules_src, Path.join(lib_dest, "modules"))
      Path.join(dest_root, "rootfs")
    end
  end
end
