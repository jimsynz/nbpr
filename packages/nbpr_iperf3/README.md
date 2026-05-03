# nbpr_iperf3

`iperf3` packaged for Nerves via [NBPR](https://github.com/jimsynz/nbpr).

## Usage

In your Nerves project's `mix.exs`:

    {:nbpr_iperf3, "~> 0.1", repo: "nbpr"}

## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_iperf3, build_opts: [
      # ...
    ]

## Note for kernel-module packages

If `NBPR.Iperf3` declares a non-empty `kernel_modules:` list, the using
project must also include `mod: {NBPR.Iperf3.Application, []}` in its
`application/0` callback so the Application is started at boot.
