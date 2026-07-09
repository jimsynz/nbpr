defmodule NBPR.Hailo8 do
  @moduledoc """
  NBPR package for the [Hailo-8 / 8L](https://hailo.ai/) AI accelerator family
  (e.g. the Raspberry Pi AI Kit / AI HAT+).

  > #### Not yet inference-validated on hardware {: .warning}
  >
  > Inference through this package has not yet been validated on Hailo-8
  > hardware. Its Hailo-10H counterpart (`:nbpr_hailo10`) is validated
  > end-to-end on device.

  Ships, version-matched to HailoRT 4.24.0:

  - **`libhailort`** — the userspace runtime, plus the `libspdlog` and
    `libprotobuf-lite` shared objects it links against. Installed into the
    package's `priv/usr/lib` and put on `LD_LIBRARY_PATH` at boot.
  - **`hailo_pci`** — the out-of-tree PCIe kernel module, built against the
    active Nerves system's kernel. Shipped in `priv/` and `insmod`'d at boot
    by the generated `NBPR.Hailo8.Application` (it isn't in the base system's
    `modules.dep`, so `modprobe` can't find it by name).
  - **Hailo-8 firmware** — installed to `/lib/firmware/hailo/hailo8_fw.bin`
    where the in-kernel firmware loader finds it when the driver probes.
  - **Dev headers + `libhailort.so`** (via `expose_staging: true`) under
    `priv/staging`, so a consumer NIF such as
    [`nx_hailo`](https://github.com/vittoriabitton/nx_hailo) can cross-compile
    against the shipped library.

  This is the Hailo-8 half of the chip-bifurcated HailoRT line. Hailo dropped
  Hailo-8/8L support in the v5 runtime/driver used by the Hailo-10H, so the two
  chips need separate, incompatible package sets — see `:nbpr_hailo10` for the
  Hailo-10H counterpart. Pick exactly one for a given device.

  ## Usage

  Add to your firmware project (with `:nbpr` and the `nbpr.fetch` alias
  installed via `mix igniter.install nbpr`):

      {:nbpr_hailo8, "~> 4.24", organization: "nbpr"}

  The driver auto-loads at boot. Point a HailoRT-linking NIF at the shipped
  SDK, e.g. for `nx_hailo`:

      # config/target.exs
      priv = :code.priv_dir(:nbpr_hailo8) |> to_string()
      config :nx_hailo,
        target: "hailo8",
        hailort_include_dir: Path.join(priv, "staging/usr/include"),
        hailort_lib_dir: Path.join(priv, "staging/usr/lib")
  """

  use NBPR.BrPackage,
    version: 1,
    br_external_path: "buildroot",
    # Dependency order: spdlog (build dep of hailort) → hailort → firmware →
    # PCIe driver (depends on hailort + the kernel).
    br_packages: ["spdlog_hailort", "hailort", "hailort-firmware", "hailort-drivers"],
    description: "HailoRT runtime, PCIe driver and firmware for Hailo-8/8L AI accelerators",
    homepage: "https://github.com/hailo-ai/hailort",
    kernel_modules: ["hailo_pci"],
    expose_staging: true,
    # Only the kernel firmware is routed to the rootfs. libhailort and its
    # unversioned proto/spdlog helpers stay in THIS package's priv so the
    # Hailo-8 and Hailo-10 runtimes never collide in /usr/lib; nx_hailo dlopens
    # the right version from here at runtime.
    rootfs_paths: ["lib/firmware"],
    targets: [:rpi5],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
