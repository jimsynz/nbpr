# nbpr_iperf3

> Iperf is a tool for active measurements of the maximum achievable bandwidth on IP networks.

[`iperf3`](http://software.es.net/iperf/index.html) packaged for Nerves.
Tracks the upstream Buildroot `iperf3` package — this release wraps
**3.19.1**.

## Usage

In your Nerves project's `mix.exs`:

    {:nbpr_iperf3, "~> 3.0", repo: "nbpr"}

Run `mix deps.get`, then `mix firmware` — the `iperf3` binary lands at
`<release>/lib/nbpr_iperf3-<vsn>/priv/usr/bin/iperf3` and
`NBPR.Application` adds it to `PATH` at boot, so you can call it from
anywhere in your app:

    {output, 0} = System.cmd("iperf3", ["-c", "iperf.example.com"])

See the [NBPR README](https://github.com/jimsynz/nbpr) for the full
integration flow.

## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_iperf3, build_opts: [
      # ...
    ]
