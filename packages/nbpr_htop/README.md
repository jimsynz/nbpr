# nbpr_htop

`htop` packaged for Nerves via [NBPR](https://github.com/jimsynz/nbpr).

## Usage

In your Nerves project's `mix.exs`:

    {:nbpr_htop, "~> 0.1", repo: "nbpr"}

## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_htop, build_opts: [
      # ...
    ]

## Note for kernel-module packages

If `NBPR.Htop` declares a non-empty `kernel_modules:` list, the using
project must also include `mod: {NBPR.Htop.Application, []}` in its
`application/0` callback so the Application is started at boot.
