# nbpr_hailo10

HailoRT runtime, PCIe driver, and firmware for the **Hailo-10H** AI accelerator
(Raspberry Pi AI HAT+ 2), packaged for Nerves via
[NBPR](https://github.com/jimsynz/nbpr).

Tracks HailoRT **5.3.0** (the v5 / `master` line). The Hailo-8/8L counterpart is
[`nbpr_hailo8`](../nbpr_hailo8); the two are incompatible — Hailo dropped
Hailo-8 support in v5 — so a device uses one or the other.

Validated end-to-end on a Hailo-10H: the package builds for
`nerves_system_rpi5`, `hailo1x_pci` probes the device, the firmware bundle
(u-boot, SCU, fitImage, signed DTBs) loads over PCIe from
`/lib/firmware/hailo/hailo10h/`, `/dev/h1x-0` appears, and inference through
`libhailort` runs on hardware.

## Usage

```elixir
{:nbpr_hailo10, "~> 5.3", organization: "nbpr"}
```

```elixir
# config/target.exs — point an nx_hailo-style NIF at the staged SDK
priv = :code.priv_dir(:nbpr_hailo10) |> to_string()

config :nx_hailo,
  target: "hailo10",
  hailort_include_dir: Path.join(priv, "staging/usr/include"),
  hailort_lib_dir: Path.join(priv, "staging/usr/lib")
```

## Licensing

`libhailort` is MIT; the `hailo1x_pci` driver is GPL-2.0. The Hailo-10H firmware
is proprietary and fetched from Hailo at build time, not redistributed here.
