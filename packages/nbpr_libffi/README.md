# nbpr_libffi

> Portable foreign-function interface library

[`libffi`](https://sourceware.org/libffi/) packaged for Nerves. Tracks the upstream Buildroot `libffi` package — this release wraps **3.4.8**.

Licence: MIT.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_libffi, "~> 3.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
