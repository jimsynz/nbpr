# nbpr_jq

> Lightweight JSON processor (`jq`) packaged for Nerves.

[`jq`](https://jqlang.github.io/jq/) packaged for Nerves. Tracks the
upstream Buildroot `jq` package — this release wraps **1.8.1**.

## Usage

In your Nerves project's `mix.exs`:

    {:nbpr_jq, "~> 1.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware` — the `jq` binary lands at
`<release>/lib/nbpr_jq-<vsn>/priv/usr/bin/jq` and `NBPR.Application`
adds it to `PATH` at boot, so you can call it from anywhere in your
app:

    {output, 0} = System.cmd("jq", [".name", "/srv/erlang/config.json"])

See the [NBPR README](https://github.com/jimsynz/nbpr) for the full
integration flow.

## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_jq, build_opts: [
      # ...
    ]
