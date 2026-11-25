# nbpr_docker_engine

> Docker is a platform to build, ship, and run applications as lightweight containers.

[`docker-engine`](https://github.com/docker/docker) packaged for Nerves. Tracks the upstream Buildroot `docker-engine` package — this release wraps **28.3.2**.

Licence: Apache-2.0.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_docker_engine, "~> 28.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
