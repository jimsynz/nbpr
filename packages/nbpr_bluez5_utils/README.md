# nbpr_bluez5_utils

> BlueZ utils

[`bluez5_utils`](http://www.bluez.org) packaged for Nerves. Tracks the upstream Buildroot `bluez5_utils` package — this release wraps **5.79**.

Licences: GPL-2.0-or-later, LGPL-2.1-or-later.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_bluez5_utils, "~> 5.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
