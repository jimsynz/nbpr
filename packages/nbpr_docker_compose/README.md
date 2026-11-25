# nbpr_docker_compose

> Multi-container applications with the Docker CLI.

[`docker-compose`](https://github.com/docker/compose) packaged for Nerves. Tracks the upstream Buildroot `docker-compose` package — this release wraps **2.38.2**.

Licence: Apache-2.0.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_docker_compose, "~> 2.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
