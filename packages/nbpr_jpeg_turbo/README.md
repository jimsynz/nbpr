# nbpr_jpeg_turbo

> SIMD-accelerated JPEG codec providing the libjpeg API

[`jpeg-turbo`](https://libjpeg-turbo.org/) packaged for Nerves. Tracks the upstream Buildroot `jpeg-turbo` package — this release wraps **3.1.4.1**.

Licences: IJG, BSD-3-Clause, Zlib.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_jpeg_turbo, "~> 3.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
