# nbpr_expat

> Stream-oriented XML parser library

[`expat`](https://libexpat.github.io/) packaged for Nerves. Tracks the upstream Buildroot `expat` package — this release wraps **2.8.2**.

Licence: MIT.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_expat, "~> 2.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
