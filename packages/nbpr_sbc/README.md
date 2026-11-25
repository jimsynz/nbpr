# nbpr_sbc

> An audio codec to connect bluetooth high quality audio devices like headphones or loudspeakers.

[`sbc`](http://www.bluez.org/) packaged for Nerves. Tracks the upstream Buildroot `sbc` package — this release wraps **2.1**.

Licence: LGPL-2.1-or-later.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_sbc, "~> 2.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
