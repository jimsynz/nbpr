# nbpr_libpcap

> A system-independent library for user-level network packet capture.

[`libpcap`](https://www.tcpdump.org/) packaged for Nerves. Tracks the upstream Buildroot `libpcap` package — this release wraps **1.10.5**.


## Usage

In your Nerves project's `mix.exs`:

    {:nbpr_libpcap, "~> 1.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware` — the binary lands at
`<release>/lib/nbpr_libpcap-<vsn>/priv/usr/...` and `NBPR.Application`
adds it to `PATH` and `LD_LIBRARY_PATH` at boot. See the
[NBPR README](https://github.com/jimsynz/nbpr) for the full
integration flow (including supervision-tree wiring for
daemon-bearing packages).

## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_libpcap, build_opts: [
      # ...
    ]
