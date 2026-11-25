# nbpr_dbus

> The D-Bus message bus system.

[`dbus`](https://www.freedesktop.org/wiki/Software/dbus) packaged for Nerves. Tracks the upstream Buildroot `dbus` package — this release wraps **1.14.10**.

Licences: AFL-2.1, GPL-2.0-or-later.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_dbus, "~> 1.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
