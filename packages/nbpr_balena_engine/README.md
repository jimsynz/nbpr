# nbpr_balena_engine

> BalenaEngine is a new container engine purpose-built for embedded and IoT use cases and compatible with Docker containers.

[`balena-engine`](https://github.com/balena-os/balena-engine) packaged for Nerves. Tracks the upstream Buildroot `balena-engine` package — this release wraps **20.10.26**.

Licence: Apache-2.0.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_balena_engine, "~> 20.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
