# nbpr_libvips

> Demand-driven image processing library and command-line tools

[`libvips`](https://www.libvips.org/) packaged for Nerves. Tracks the upstream Buildroot `libvips` package — this release wraps **8.18.0**.

Licence: LGPL-2.1-or-later.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_libvips, "~> 8.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
