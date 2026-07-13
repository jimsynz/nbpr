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
    `libprotobuf-lite` shared objects it links against. Routed to `/usr/lib`
    (the dynamic loader's default path), so both spawned binaries and NIFs
    linking `-lhailort` resolve them with no extra setup.
  - **`hailo_pci`** — the out-of-tree PCIe kernel module, built against the
    active Nerves system's kernel. Shipped in `priv/` and `insmod`'d at boot
    by the generated `NBPR.Hailo8.Application` (it isn't in the base system's
    `modules.dep`, so `modprobe` can't find it by name).
  - **Hailo-8 firmware** — installed to `/lib/firmware/hailo/hailo8_fw.bin`
    where the in-kernel firmware loader finds it when the driver probes.
  - **Dev headers + `libhailort.so`** (via `expose_staging: true`) under
    `priv/staging`, so a consumer NIF can cross-compile against the shipped
    library.

  This is the Hailo-8 half of the chip-bifurcated HailoRT line. Hailo dropped
  Hailo-8/8L support in the v5 runtime/driver used by the Hailo-10H, so the two
  chips need separate, incompatible package sets — see `:nbpr_hailo10` for the
  Hailo-10H counterpart.

  > #### One hailo package per firmware image {: .warning}
  >
  > `:nbpr_hailo8` and `:nbpr_hailo10` must not be installed in the same
  > firmware: both route helper libraries with identical sonames
  > (`libprotobuf-lite.so.32`, `libspdlog`) to `/usr/lib`, where the last
  > overlay write silently wins. Build one image per chip.

  ## Usage

  Add to your firmware project (with `:nbpr` and the `nbpr.fetch` alias
  installed via `mix igniter.install nbpr`):

      {:nbpr_hailo8, "~> 4.24", organization: "nbpr"}

  The driver auto-loads at boot and `libhailort` is on the loader's default
  path, so a NIF just links `-lhailort`. It cross-compiles against the staged
  SDK, e.g.:

      # config/target.exs
      priv = :code.priv_dir(:nbpr_hailo8) |> to_string()
      config :my_hailo_nif,
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
    # Firmware goes where the in-kernel loader looks; the shared libraries go
    # to /usr/lib, the loader's default path, so a NIF linking -lhailort
    # resolves them with no loader tricks. This is why only one hailo package
    # can ship per firmware image (see moduledoc).
    rootfs_paths: ["lib/firmware", "usr/lib"],
    targets: [:rpi5],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
