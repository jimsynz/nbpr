defmodule NBPR.Hailo10 do
  @moduledoc """
  NBPR package for the [Hailo-10H](https://hailo.ai/) AI accelerator
  (e.g. the Raspberry Pi AI HAT+ 2 / "AI Kit 2").

  > #### Hardware-validated on a Hailo-10H {: .info}
  >
  > Builds for `nerves_system_rpi5` and runs end-to-end on real hardware —
  > `hailo1x_pci` probes `1e60:45c4`, loads the SOC firmware over PCIe, creates
  > `/dev/h1x-0`, and inference through `libhailort` has been validated on
  > device. The firmware installs to `/lib/firmware/hailo/hailo10h/` (the exact
  > path the driver's `request_firmware()` uses).

  Ships, version-matched to HailoRT 5.3.0 (the `master`/v5 line):

  - **`libhailort`** (v5) plus its `libspdlog` / `libprotobuf-lite` deps.
  - **`hailo1x_pci`** — the v5 PCIe kernel module (distinct module name from the
    Hailo-8 `hailo_pci`), built against the active Nerves system kernel and
    `insmod`'d at boot.
  - **Hailo-10H firmware bundle** (u-boot, SCU, fitImage, signed DTBs) under
    `/lib/firmware/hailo/`.
  - **Dev headers + `libhailort.so`** under `priv/staging` for NIF
    cross-compilation (`expose_staging: true`).

  This is the Hailo-10H half of the chip-bifurcated HailoRT line; the Hailo-8/8L
  counterpart is `:nbpr_hailo8`. The two runtimes/drivers are incompatible, and
  the two packages must not ship in the same firmware image — both route helper
  libraries with identical sonames to `/usr/lib`, where the last overlay write
  silently wins. Build one image per chip. `libhailort` sits on the loader's
  default path, so a NIF just links `-lhailort` (see `NBPR.Hailo8` for a
  consumer example).
  """

  use NBPR.BrPackage,
    version: 1,
    br_external_path: "buildroot",
    br_packages: ["spdlog_hailort", "hailort", "hailort-firmware", "hailort-drivers"],
    description: "HailoRT v5 runtime, PCIe driver and firmware for Hailo-10H AI accelerators",
    homepage: "https://github.com/hailo-ai/hailort",
    kernel_modules: ["hailo1x_pci"],
    expose_staging: true,
    # Firmware goes where the in-kernel loader looks; the shared libraries go
    # to /usr/lib, the loader's default path, so a NIF linking -lhailort
    # resolves them with no loader tricks. This is why only one hailo package
    # can ship per firmware image (see moduledoc).
    rootfs_paths: ["lib/firmware", "usr/lib"],
    targets: [:rpi5],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
