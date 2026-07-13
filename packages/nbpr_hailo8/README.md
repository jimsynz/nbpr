# nbpr_hailo8

HailoRT runtime, PCIe driver, and firmware for the **Hailo-8 / 8L** AI
accelerator family (Raspberry Pi AI Kit, AI HAT+, etc.), packaged for Nerves
via [NBPR](https://github.com/jimsynz/nbpr).

Tracks HailoRT **4.24.0** (the `hailo8` branch of HailoRT — Hailo-8/8L are not
supported by the v5 runtime/driver; for the Hailo-10H see `:nbpr_hailo10`).

Inference through this package has not yet been validated on Hailo-8 hardware;
the Hailo-10H counterpart is validated end-to-end.

## What's in the artefact

| Component | Where it lands | How it's used |
| --- | --- | --- |
| `libhailort.so` (+ `libspdlog`, `libprotobuf-lite`) | `priv/usr/lib` | spawned binaries: `LD_LIBRARY_PATH`; NIFs: consumer pre-`dlopen`s by path |
| `hailo_pci.ko` | `priv/lib/modules/...` | `insmod`'d at boot by `NBPR.Hailo8.Application` |
| `hailo8_fw.bin` | `/lib/firmware/hailo/` | loaded by the driver on probe |
| headers + `libhailort.so` dev symlink | `priv/staging` | NIF cross-compilation (`expose_staging`) |

The PCIe driver is an out-of-tree kernel module built against the active Nerves
system's kernel, so the prebuilt artefact is specific to a
`(nerves_system_rpi5, version)` pair. On a system/version with no prebuilt, NBPR
source-builds it (this compiles the kernel as a Buildroot dependency — slow the
first time, then cached).

## Usage

In a Nerves firmware project that has installed NBPR (`mix igniter.install nbpr`,
which adds `:nbpr` and the `firmware: ["nbpr.fetch", "firmware"]` alias):

```elixir
# mix.exs
{:nbpr_hailo8, "~> 4.24", organization: "nbpr"}
```

The driver loads automatically at boot. To build a HailoRT-linking NIF against
the shipped SDK, point it at the staged headers/libs:

```elixir
# config/target.exs
priv = :code.priv_dir(:nbpr_hailo8) |> to_string()

config :my_hailo_nif,
  hailort_include_dir: Path.join(priv, "staging/usr/include"),
  hailort_lib_dir: Path.join(priv, "staging/usr/lib")
```

`mix nbpr.fetch` (run automatically before `mix firmware`) must populate the
package's `priv/` before the NIF compiles, so build with `mix firmware` rather
than a bare `mix compile`.

At runtime the NIF cannot resolve `libhailort` from `priv` via
`LD_LIBRARY_PATH` (the loader captures it at process start). The consumer must
`dlopen` the libs in this package's `priv/usr/lib` by absolute path with
`RTLD_GLOBAL` before loading its NIF — see the `NBPR.Hailo8` moduledoc. This
namespacing is also what lets `nbpr_hailo8` and `nbpr_hailo10` ship in the same
image.

## Licensing

`libhailort` is MIT; the `hailo_pci` driver is GPL-2.0. The Hailo-8 firmware is
proprietary and is fetched from Hailo's distribution at build time — it is not
redistributed in this Hex package.
