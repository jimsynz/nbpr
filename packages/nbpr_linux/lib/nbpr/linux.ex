defmodule NBPR.Linux do
  @moduledoc """
  Rebuilds the active Nerves system's Linux kernel with extra configuration
  and patches, and injects the result into the firmware.

  Unlike the userspace `nbpr_*` packages, this one carries no binary of its
  own. It pins to the **kernel version the system already ships** (reusing the
  system's `nerves_defconfig`, untouched tarball location) and layers your
  customisation on top:

      # config/target.exs
      config :nbpr_linux,
        config_fragments: ["config/linux/wireguard.fragment"],
        patches: ["config/linux/0001-vendor-fix.patch"]

  At `mix firmware` time, `mix nbpr.fetch` rebuilds the kernel, ships the
  in-tree modules via the rootfs overlay, and points `NERVES_SYSTEM` at a
  shadow system directory whose kernel image and device trees are the rebuilt
  ones — leaving the shared Nerves artefact cache untouched.

  Add it to a target's deps:

      {:nbpr_linux, "~> 0.1", targets: [:rpi4], organization: "nbpr"}

  The same dep works across targets; per-target customisation lives in config.
  """

  use NBPR.BrPackage,
    version: 1,
    kernel: true,
    description: "Rebuilds the Nerves system Linux kernel with extra config and patches",
    homepage: "https://github.com/jimsynz/nbpr",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
