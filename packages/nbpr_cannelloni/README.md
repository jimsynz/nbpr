# nbpr_cannelloni

> SocketCAN over Ethernet tunnel.

[`cannelloni`](https://github.com/mguentner/cannelloni) packaged for Nerves. Tracks the upstream Buildroot `cannelloni` package — this release wraps **2.1.2**.

Licence: GPL-2.0-only.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_cannelloni, "~> 2.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.


## What you get

`cannelloni` at `/usr/bin/cannelloni`, `libcannelloni-common.so.0` beside
it, and a generated `NBPR.Cannelloni.Cannelloni` — a MuonTrap-supervised
GenServer you add to your own supervision tree:

```elixir
children = [
  {NBPR.Cannelloni.Cannelloni, can_interface: "can0", remote_address: "10.0.0.2"}
]
```

It lifts frames off a local CAN interface, batches them, and ships them to a
peer running the same program, which writes them onto its own interface — so
a device with no CAN controller can work a bus attached to one that has.
Both ends run cannelloni; there is no separate server. `NBPR.Cannelloni`'s
docs carry the full runtime option schema.

UDP is the default transport and the one the protocol was built around:
frames are batched until `buffer_timeout_us` elapses and then sent as one
datagram, so a busy bus costs far fewer packets than a datagram per frame.
`transport: :tcp_client` / `:tcp_server` is there for paths that won't carry
UDP.

Two things deliberately aren't in the option schema:

- **SCTP.** Buildroot gates it on `BR2_PACKAGE_LKSCTP_TOOLS`, which would
  need an `:nbpr_lksctp_tools` package, and the kernel's `CONFIG_IP_SCTP`
  besides. The binary's `-S` is compiled out, not defaulted off.
- **Daemon mode** (`-f`, `-P`). cannelloni stays in the foreground unless
  told otherwise, which is what MuonTrap needs — forking would hand the
  GenServer a pid that exits immediately and leave the real process
  unsupervised.


## Kernel requirements

Both ends open a raw CAN socket, so each needs `CONFIG_CAN`,
`CONFIG_CAN_RAW` and a driver for its interface. Stock Nerves systems enable
none of them — see [`nbpr_can_utils`](../nbpr_can_utils) for the
full list and what to ask a system maintainer for. On the end with no
controller, `CONFIG_CAN_VCAN` is enough: a `vcan0` is a perfectly good
tunnel endpoint.

cannelloni is C++ and links `libstdc++.so.6`. Buildroot makes the package
depend on `BR2_INSTALL_LIBSTDCPP`, so a system without it fails the build
rather than shipping a broken artefact. Every built system artefact to hand
(rpi0_2, rpi4, rpi5, x86_64) sets it and carries the library in its rootfs,
so there's nothing extra to ship.

Source: <https://github.com/jimsynz/nbpr>.
