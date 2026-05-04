# nbpr_htop

> Htop is an interactive text-mode process viewer for Linux.

[`htop`](https://htop.dev/) packaged for Nerves. Tracks the upstream
Buildroot `htop` package — this release wraps **3.4.1**.

## Usage

In your Nerves project's `mix.exs`:

    {:nbpr_htop, "~> 3.0", repo: "nbpr"}

Run `mix deps.get`, then `mix firmware` — the `htop` binary lands at
`<release>/lib/nbpr_htop-<vsn>/priv/usr/bin/htop` and `NBPR.Application`
adds it to `PATH` at boot. SSH into your device and run `htop` to get
an interactive process viewer.

See the [NBPR README](https://github.com/jimsynz/nbpr) for the full
integration flow.

## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_htop, build_opts: [
      # ...
    ]
