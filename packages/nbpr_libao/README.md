# nbpr_libao

> Cross-platform audio output library.

[`libao`](https://www.xiph.org/ao/) packaged for Nerves. Tracks the upstream
Buildroot `libao` package — this release wraps **1.2.2**.

Licence: GPL-2.0-or-later.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_libao, "~> 1.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Usually you won't add this directly — it arrives as a dependency of
[`nbpr_vorbis_tools`](../nbpr_vorbis_tools), which is the only thing
linking it today.


## Why it exists

No Nerves system ships libao. Checked against the built system artefacts in
the local cache — `rpi0` 2.0.4, `rpi4` 2.1.1, `rpi5` 0.7.0, `bbb` 2.29.5,
`trellis` 0.4.2 and `x86_64` 1.30.1 — none has `libao.so.4` in staging.

Buildroot's vorbis-tools `select`s libao unconditionally, so `ogg123` always
links it, and an nbpr artefact carries only its own Buildroot files-list.


## Live audio output does not work yet

libao locates its output plugins by `opendir` on a path fixed at build time
— `/usr/lib/ao/plugins-4`, Buildroot's `libdir`. nbpr installs a package's
files under its own `priv/` rather than at rootfs paths, and libao has no
environment variable to redirect the search: `ao_load_plugins()` in
`audio_out.c` uses the compiled-in `AO_PLUGIN_PATH` verbatim.

So on a Nerves target that directory is empty and only the drivers compiled
into the library itself are available — `wav`, `au`, `raw` and `null`. Good
enough to transcode to a file, not enough to drive a speaker.

Fixing it means installing the plugin directory at its rootfs path instead
of into `priv/`. The `rootfs/` artefact slice that `NBPR.Pack` already
carries for kernel modules is the mechanism; the Buildroot harvest step
doesn't populate it yet.


## Which plugin gets built

Buildroot enables libao's ALSA plugin when the system has `alsa-lib` and
falls back to OSS when it doesn't, so the artefact isn't the same on every
target:

| Systems                          | Plugin built  |
| -------------------------------- | ------------- |
| `rpi0`, `rpi0_2`, `rpi3`, `rpi3a`, `rpi4`, `rpi5` | `libalsa.so` |
| `bbb`, `x86_64`, `trellis`, `qemu_aarch64`        | `liboss.so`  |

Neither loads today, per above.

Source: <https://github.com/jimsynz/nbpr>.
