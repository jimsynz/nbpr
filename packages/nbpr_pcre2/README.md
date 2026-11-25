# nbpr_pcre2

> Perl-compatible regular expression library

[`pcre2`](https://www.pcre.org/) packaged for Nerves. Tracks the upstream Buildroot `pcre2` package — this release wraps **10.47**.

Licence: BSD-3-Clause.


## Usage

Add this package to your Nerves project's `mix.exs`:

    {:nbpr_pcre2, "~> 10.0"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.
