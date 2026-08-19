# nbpr_fftw_single

> Library for computing Fast Fourier Transforms, single precision.

[`fftw`](http://www.fftw.org) packaged for Nerves. Tracks the upstream
Buildroot `fftw-single` package — this release wraps **3.3.10**.

Licence: GPL-2.0-or-later.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_fftw_single, "~> 3.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.


## Which precision do I want?

Buildroot builds each fftw precision as a separate package from one
tarball, each producing its own library with its own soname, and NBPR
follows that split. Pick by which library your code links:

| Package              | Library            | Symbols  | Link flag  |
| -------------------- | ------------------ | -------- | ---------- |
| `nbpr_fftw_single`   | `libfftw3f.so.3`   | `fftwf_*`| `-lfftw3f` |
| `nbpr_fftw_double`   | `libfftw3.so.3`    | `fftw_*` | `-lfftw3`  |

The two don't conflict. Code that links both — as Eigen's FFT bindings
do — wants both packages in the firmware:

    {:nbpr_fftw_single, "~> 3.0", organization: "nbpr"},
    {:nbpr_fftw_double, "~> 3.0", organization: "nbpr"}

If you just want "FFTW" and aren't sure, take double precision: it's
what `-lfftw3` and the plain `fftw_*` API refer to, and it's the
precision Buildroot itself defaults to.

Buildroot also has long-double and quad-precision variants. Neither is
packaged here yet; quad is x86-only in any case, since kconfig hides it
without gcc's `__float128`.


## Why it exists

No Nerves system ships fftw. Checked against the built system artefacts
for `rpi4` 2.1.0, `rpi5` 0.7.0 and `bbb` 2.29.5 — none has any
`libfftw3*` in staging.

The library also isn't much use to a NIF unless the headers and the
`.so` symlink are available at cross-compile time, so this package's
staging slice carries both, alongside the runtime library that lands in
the rootfs.


## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_fftw_single, build_opts: [fast: true]

`fast` builds with `-O3 -ffast-math`, trading accuracy for speed. It's
off by default, matching Buildroot — say yes only if you need the speed
and can live with inaccurate results.

On ARM targets with NEON and hard-float, Buildroot builds this package
with `--enable-neon` regardless. Single precision is the only variant
NEON applies to.

Source: <https://github.com/jimsynz/nbpr>.
