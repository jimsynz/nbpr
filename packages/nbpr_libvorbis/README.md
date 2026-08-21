# nbpr_libvorbis

> Reference encoder and decoder for the Ogg Vorbis audio codec.

[`libvorbis`](https://xiph.org/vorbis/) packaged for Nerves. Tracks the
upstream Buildroot `libvorbis` package — this release wraps **1.3.7**.

Licence: BSD-3-Clause.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_libvorbis, "~> 1.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Usually you won't add this directly — it arrives as a dependency of a
package that links it.


## Why it exists

No Nerves system ships libvorbis. Checked against the built system
artefacts in the local cache — `rpi0` 2.0.4, `rpi4` 2.1.1, `rpi5` 0.7.0,
`bbb` 2.29.5, `trellis` 0.4.2 and `x86_64` 1.30.1 — none has any
`libvorbis*` in staging.

[`nbpr_vorbis_tools`](../nbpr_vorbis_tools) links all three of its
libraries, and anything decoding Vorbis from a NIF will want them too.


## What's in it

Three libraries, all of which link `libogg.so.0` — hence the
[`nbpr_libogg`](../nbpr_libogg) dependency:

| Library                | What it does                                |
| ---------------------- | ------------------------------------------- |
| `libvorbis.so.0`       | the codec itself                            |
| `libvorbisenc.so.2`    | encoder setup (bitrate management, modes)   |
| `libvorbisfile.so.3`   | convenience decoding layer over Ogg streams |

`staging/` carries the headers, `.so` symlinks and pkg-config files for
cross-compiling a NIF against them.

For the command-line tools built on this codec — `oggenc`, `oggdec`,
`ogg123`, `vorbiscomment` — see
[`nbpr_vorbis_tools`](../nbpr_vorbis_tools).

Source: <https://github.com/jimsynz/nbpr>.
