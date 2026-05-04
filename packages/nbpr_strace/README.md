# nbpr_strace

> A useful diagnostic, instructional, and debugging tool.

[`strace`](https://strace.io) packaged for Nerves. Tracks the upstream Buildroot `strace` package — this release wraps **6.18**.


## Usage

In your Nerves project's `mix.exs`:

    {:nbpr_strace, "~> 6.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware` — the binary lands at
`<release>/lib/nbpr_strace-<vsn>/priv/usr/...` and `NBPR.Application`
adds it to `PATH` and `LD_LIBRARY_PATH` at boot. See the
[NBPR README](https://github.com/jimsynz/nbpr) for the full
integration flow (including supervision-tree wiring for
daemon-bearing packages).

## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_strace, build_opts: [
      # ...
    ]
