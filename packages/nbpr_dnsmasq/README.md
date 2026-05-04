# nbpr_dnsmasq

> Lightweight DHCP/DNS server (`dnsmasq`) packaged for Nerves.

[`dnsmasq`](https://thekelleys.org.uk/dnsmasq/doc.html) packaged for
Nerves. Tracks the upstream Buildroot `dnsmasq` package — this release
wraps **2.91**.

## Usage

In your Nerves project's `mix.exs`:

    {:nbpr_dnsmasq, "~> 2.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware` — the `dnsmasq` binary lands
at `<release>/lib/nbpr_dnsmasq-<vsn>/priv/usr/sbin/dnsmasq` and
`NBPR.Application` adds it to `PATH` at boot.

This package generates a `NBPR.Dnsmasq.Dnsmasq` daemon module via the
`NBPR.BrPackage` macro. Add it to your app's supervision tree to run
dnsmasq under MuonTrap supervision:

    children = [
      {NBPR.Dnsmasq.Dnsmasq, config_file: "/etc/dnsmasq.conf"}
    ]

Ship the config file via `rootfs_overlay/etc/dnsmasq.conf` (the standard
Nerves overlay path). See `NBPR.Dnsmasq.Dnsmasq`'s `@moduledoc` for the
full options schema.

## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_dnsmasq, build_opts: [
      # ...
    ]
