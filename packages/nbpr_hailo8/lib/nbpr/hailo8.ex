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
    package's `priv/usr/lib`; on `LD_LIBRARY_PATH` at boot for spawned
    binaries (a NIF consumer loads it differently — see below).
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
  Hailo-10H counterpart. One firmware image may ship both packages (their libs
  are namespaced per package in `priv`, so they never collide), but a VM
  session loads exactly one runtime.

  ## Usage

  Add to your firmware project (with `:nbpr` and the `nbpr.fetch` alias
  installed via `mix igniter.install nbpr`):

      {:nbpr_hailo8, "~> 4.24", organization: "nbpr"}

  The driver auto-loads at boot. A HailoRT-linking NIF cross-compiles against
  the staged SDK, e.g.:

      # config/target.exs
      priv = :code.priv_dir(:nbpr_hailo8) |> to_string()
      config :my_hailo_nif,
        hailort_include_dir: Path.join(priv, "staging/usr/include"),
        hailort_lib_dir: Path.join(priv, "staging/usr/lib")

  ## Runtime loading for NIF consumers

  `LD_LIBRARY_PATH` is captured by the dynamic loader at process start, so the
  env this package exports at boot serves *spawned* binaries only — a NIF's
  `DT_NEEDED` cannot resolve `libhailort` from `priv` through it. A NIF
  consumer must therefore `dlopen` each shared object in this package's
  `priv/usr/lib` by absolute path with `RTLD_GLOBAL` (via a small
  dependency-free loader NIF) *before* loading its own NIF; the NIF's
  references then resolve by soname against the already-loaded libraries.
  This keeps each chip's runtime namespaced to its package, which is what
  allows hailo8 and hailo10 to coexist in one image.
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
    # Hailo-8 and Hailo-10 runtimes never collide in /usr/lib; a NIF consumer
    # pre-loads the right version from here by absolute path (see moduledoc).
    rootfs_paths: ["lib/firmware"],
    targets: [:rpi5],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
