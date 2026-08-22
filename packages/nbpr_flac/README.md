# nbpr_flac

> Free Lossless Audio Codec libraries and command-line tools.

[`flac`](https://xiph.org/flac/) packaged for Nerves. Tracks the upstream
Buildroot `flac` package — this release wraps **1.5.0**.

Licences: BSD-3-Clause, GPL-2.0-or-later, LGPL-2.1-or-later.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_flac, "~> 1.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.


## What's in it

Two binaries, on `PATH` at boot, so `System.cmd/2` finds them by name:

| Binary      | What it does                                              |
| ----------- | --------------------------------------------------------- |
| `flac`      | encode and decode FLAC, verify streams, test integrity    |
| `metaflac`  | edit tags and STREAMINFO in place, without re-encoding    |

For example:

```elixir
{_output, 0} = System.cmd("flac", ["--best", "-o", "/data/out.flac", "/data/in.wav"])
{tags, 0} = System.cmd("metaflac", ["--export-tags-to=-", "/data/out.flac"])
```

Plus the libraries they're built on — `libFLAC.so.14`, and `libFLAC++.so.11`
because Nerves toolchains ship a C++ compiler. Both are on
`LD_LIBRARY_PATH`, with headers and pkg-config files in the staging slice
for a NIF that would rather link the codec than shell out.

No Nerves system ships any of it: checked against the built system
artefacts in the local cache — `rpi0` 2.0.4, `rpi4` 2.1.1, `rpi5` 0.7.0,
`bbb` 2.29.5, `trellis` 0.4.2 and `x86_64` 1.30.1 — none has `libFLAC*` in
staging.


## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_flac, build_opts: [ogg: false]

`ogg` is on by default, which is why this package depends on
[`nbpr_libogg`](../nbpr_libogg). Without it Buildroot configures
`--disable-ogg` and `libFLAC` loses the Ogg-FLAC container — `.oga` files,
and `flac --ogg`. Native `.flac` is unaffected either way.

The dependency stays regardless of the option: a Hex dependency can't be
conditional on a build option, so an `ogg: false` firmware carries libogg
unused. Drop it from your own deps if that matters — but nothing else will
resolve `libogg.so.0` for a sibling package that needs it.

Build options are part of the artefact cache key, so a non-default value
has no prebuilt artefact to match and falls to a source build.


## Which licence applies

Three, and which binds depends on what you ship. `libFLAC` and `libFLAC++`
are BSD-3-Clause; the `flac` and `metaflac` binaries are GPL-2.0-or-later;
the remaining support libraries are LGPL-2.1-or-later. Linking the
libraries from a NIF is not the same proposition as shipping the tools —
the artefact's `legal-info/` slice carries the upstream texts.

Source: <https://github.com/jimsynz/nbpr>.
