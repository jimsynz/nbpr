# nbpr_docker_cli_buildx

> Buildx is a Docker CLI plugin for extended build capabilities with BuildKit.

[`docker-cli-buildx`](https://github.com/docker/buildx) packaged for Nerves. Tracks the upstream Buildroot `docker-cli-buildx` package — this release wraps **0.25.0**.

Licence: Apache-2.0.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_docker_cli_buildx, "~> 0.1"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
