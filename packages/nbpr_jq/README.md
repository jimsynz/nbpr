# nbpr_jq

`jq` packaged for Nerves via [NBPR](https://github.com/nerves-project/nbpr).

## Usage

In your Nerves project's `mix.exs`:

    {:nbpr_jq, "~> 0.1", repo: "nbpr"}

## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_jq, build_opts: [
      # ...
    ]

## Note for kernel-module packages

If `NBPR.Jq` declares a non-empty `kernel_modules:` list, the using
project must also include `mod: {NBPR.Jq.Application, []}` in its
`application/0` callback so the Application is started at boot.
