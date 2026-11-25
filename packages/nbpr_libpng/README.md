# nbpr_libpng

> Library for reading and writing PNG images

[`libpng`](http://www.libpng.org/) packaged for Nerves. Tracks the upstream Buildroot `libpng` package — this release wraps **1.6.58**.

Licence: libpng-2.0.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_libpng, "~> 1.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
