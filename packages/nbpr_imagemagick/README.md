# nbpr_imagemagick

> Image conversion and manipulation suite

[`imagemagick`](https://imagemagick.org/) packaged for Nerves. Tracks the upstream Buildroot `imagemagick` package — this release wraps **7.1.2-26**.

Licence: Apache-2.0.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_imagemagick, "~> 7.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
