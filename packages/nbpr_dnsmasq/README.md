# nbpr_dnsmasq

`dnsmasq` packaged for Nerves via [NBPR](https://github.com/nerves-project/nbpr).

## Usage

In your Nerves project's `mix.exs`:

    {:nbpr_dnsmasq, "~> 0.1", repo: "nbpr"}

## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_dnsmasq, build_opts: [
      # ...
    ]

## Note for kernel-module packages

If `NBPR.Dnsmasq` declares a non-empty `kernel_modules:` list, the using
project must also include `mod: {NBPR.Dnsmasq.Application, []}` in its
`application/0` callback so the Application is started at boot.
