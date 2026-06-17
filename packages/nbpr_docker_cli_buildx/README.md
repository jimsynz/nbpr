# nbpr_docker_cli_buildx

> Buildx is a Docker CLI plugin for extended build capabilities with BuildKit.

[`docker-cli-buildx`](https://github.com/docker/buildx) packaged for Nerves. Tracks the upstream Buildroot `docker-cli-buildx` package — this release wraps **0.25.0**.

Licence: Apache-2.0.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_docker_cli_buildx, "~> 0.1", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
