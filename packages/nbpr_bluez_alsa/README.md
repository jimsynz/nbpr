# nbpr_bluez_alsa

> Bluetooth Audio ALSA Backend.

[`bluez-alsa`](https://github.com/Arkq/bluez-alsa) packaged for Nerves. Tracks the upstream Buildroot `bluez-alsa` package — this release wraps **4.3.1**.

Licence: MIT.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_bluez_alsa, "~> 4.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
