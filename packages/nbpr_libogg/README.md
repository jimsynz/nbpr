# nbpr_libogg

> Reference implementation of the Ogg container format.

[`libogg`](https://xiph.org/ogg/) packaged for Nerves. Tracks the upstream
Buildroot `libogg` package — this release wraps **1.3.6**.

Licence: BSD-3-Clause.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_libogg, "~> 1.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Usually you won't add this directly — it arrives as a dependency of a
package that links it.


## Why it exists

No Nerves system ships libogg. Checked against the built system artefacts in
the local cache — `rpi0` 2.0.4, `rpi4` 2.1.1, `rpi5` 0.7.0, `bbb` 2.29.5,
`trellis` 0.4.2 and `x86_64` 1.30.1 — none has `libogg.so.0` in staging.

Ogg is the container the Xiph codecs store packets in, so most of them link
it: Buildroot's libvorbis `select`s it unconditionally, vorbis-tools does
too, and flac needs it for the Ogg-FLAC container. An nbpr artefact carries
only its own Buildroot files-list, so the library arrives as its own
package rather than riding along inside theirs.


## What's in it

`target/` ships `libogg.so.0` for the rootfs. `staging/` carries the
headers, the `.so` symlink and `ogg.pc` so a NIF can cross-compile against
it.

Nothing here encodes or decodes audio — Ogg is only the wrapper. For codecs
see [`nbpr_libvorbis`](../nbpr_libvorbis) and
[`nbpr_flac`](../nbpr_flac); for command-line tools,
[`nbpr_vorbis_tools`](../nbpr_vorbis_tools).

Source: <https://github.com/jimsynz/nbpr>.
