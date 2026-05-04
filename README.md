# NBPR

**Nerves Binary Package Repository** — a curated Hex repo for distributing
Buildroot-built target binaries to Nerves firmware projects. Declare
`{:nbpr_jq, "~> 1.0", organization: "nbpr"}` in your app's `mix.exs` and the
binary lands in your rootfs at firmware-build time. Daemon-bearing packages
additionally generate MuonTrap-supervised modules you add to your supervision
tree.

## Catalogue

| Package | Version | Description |
| --- | --- | --- |
| [`:nbpr_dnsmasq`](https://hex.pm/packages/nbpr/nbpr_dnsmasq) | 2.91.0 | Lightweight DHCP/DNS server (with daemon module) |
| [`:nbpr_htop`](https://hex.pm/packages/nbpr/nbpr_htop) | 3.4.1 | Interactive process viewer |
| [`:nbpr_iperf3`](https://hex.pm/packages/nbpr/nbpr_iperf3) | 3.19.1 | Network throughput measurement tool |
| [`:nbpr_jq`](https://hex.pm/packages/nbpr/nbpr_jq) | 1.8.1 | Lightweight JSON processor |
| [`:nbpr_libpcap`](https://hex.pm/packages/nbpr/nbpr_libpcap) | 1.10.5 | System-independent packet-capture library |
| [`:nbpr_strace`](https://hex.pm/packages/nbpr/nbpr_strace) | 6.18.0 | System-call tracer |
| [`:nbpr_tcpdump`](https://hex.pm/packages/nbpr/nbpr_tcpdump) | 4.99.5 | Network monitoring and packet-capture CLI |

Each version mirrors the upstream Buildroot package version. Bumps follow
upstream Buildroot releases automatically.

## Using NBPR in your Nerves app

The `:nbpr` library itself lives on public hex.pm. The binary packages
(`:nbpr_*`) live in the `nbpr` Hex organisation; authenticate once per
machine with the org's public read key:

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

The key is read-only and intentionally public — it gates package fetches
without gating discoverability. Don't use it for publishing (no publish
scope).

In your app's `mix.exs`, declare the library plus the packages you need
and alias `mix firmware` to run `mix nbpr.fetch` first:

```elixir
def project do
  [
    # ...
    aliases: ["firmware": ["nbpr.fetch", "firmware"]],
    deps: deps()
  ]
end

defp deps do
  [
    # ...
    {:nbpr, "~> 0.2"},
    {:nbpr_jq, "~> 1.0", organization: "nbpr"},
    {:nbpr_dnsmasq, "~> 2.0", organization: "nbpr"}
  ]
end
```

Then build as usual:

```sh
export MIX_TARGET=rpi4
mix deps.get
mix firmware
mix burn
```

`mix nbpr.fetch` walks your loaded apps for `:nbpr_*` packages, pulls each
one's prebuilt artefact from GHCR (or source-builds via Buildroot when no
prebuild exists for your target/system-version combo), and copies the
binaries into the package's `priv/`. At boot, `NBPR.Application` adds them
to `PATH` and `LD_LIBRARY_PATH`, so you can call them from anywhere in your
app:

```elixir
{output, 0} = System.cmd("jq", [".name", "/srv/erlang/config.json"])
```

### Daemon-bearing packages

Packages declaring daemons (e.g. `:nbpr_dnsmasq`) generate a nested module
you add to your supervision tree:

```elixir
children = [
  {NBPR.Dnsmasq.Dnsmasq, config_file: "/etc/dnsmasq.conf"}
]
```

The macro handles option validation (NimbleOptions schema), argv assembly,
binary path resolution (`:code.priv_dir/1`), and MuonTrap supervision. See
each package's README and the generated module's `@moduledoc` for specifics.

## Adding a new package

This repo is also where new `:nbpr_*` packages get authored. Scaffold one
with the generator:

    MIX_TARGET=rpi4 mix deps.get        # so deps/nerves_system_br/ exists
    mix nbpr.new <buildroot-package-name>

`mix nbpr.new` reads the workspace's pinned Buildroot tree, validates the
upstream package's licence(s) against SPDX, and bakes version, homepage,
description, and starter test/README content directly into the scaffold.
You finish by reviewing the generated `lib/nbpr/<name>.ex` and adding any
`build_opts:` or `daemons:` declarations the package needs.

PRs welcome. Tag-driven CI publishes new packages to the `nbpr` org on
push.

## Workspace layout

```
nbpr/
├── nbpr/                     # the `:nbpr` library
├── packages/
│   ├── nbpr_dnsmasq/
│   ├── nbpr_htop/
│   ├── nbpr_iperf3/
│   ├── nbpr_jq/
│   ├── nbpr_libpcap/
│   ├── nbpr_strace/
│   └── nbpr_tcpdump/
├── mix.exs                   # build harness (pulls in :nerves and target systems)
└── CLAUDE.md                 # scope, conventions, design decisions
```

The workspace `mix.exs` pulls in `:nerves` plus whichever `:nerves_system_*`
matches `MIX_TARGET`, so source-builds and the metadata generator have a
real Nerves environment to resolve against.

## Licence

Apache-2.0.
