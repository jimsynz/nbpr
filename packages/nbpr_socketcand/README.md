# nbpr_socketcand

> Daemon providing access to CAN interfaces over TCP.

[`socketcand`](https://github.com/linux-can/socketcand) packaged for Nerves. Tracks the upstream Buildroot `socketcand` package — this release wraps the **`0.6.1-103-g6dd5d33`** snapshot Buildroot pins.

Licences: BSD-3-Clause, GPL-2.0-only.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_socketcand, "~> 0.1", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

**The version above is nbpr's own, not socketcand's.** Buildroot pins a
git-describe snapshot that hex.pm can't hold, so the two are decoupled —
`0.1.0` says nothing about which socketcand you get. `mix nbpr.inspect
NBPR.Socketcand` prints the upstream version; `docs/reference/versioning.md`
in the nbpr repository explains why, under "Decoupling".


## What you get

Two binaries — `socketcand` at `/usr/sbin/socketcand` and `socketcandcl` at
`/usr/bin/socketcandcl` — and a MuonTrap-supervised GenServer for each, to
add to your own supervision tree.

`NBPR.Socketcand.Socketcand` is the server, and the one most people want:

```elixir
children = [
  {NBPR.Socketcand.Socketcand, interfaces: ["can0"], listen_interface: "wlan0"}
]
```

A client connects over TCP, says which bus it wants, and then reads and
writes frames as lines of ASCII. That makes it the way to reach a device's
CAN bus from somewhere else — a laptop running
[python-can](https://python-can.readthedocs.io/)'s `socketcand` backend, or
anything else that speaks the protocol.

`NBPR.Socketcand.Socketcandcl` is the other half: it connects to a remote
socketcand and mirrors one of *its* buses onto a local interface, so a bus
attached to another machine looks local to anything here that speaks
`AF_CAN`.

```elixir
children = [
  {NBPR.Socketcand.Socketcandcl,
   server: "10.0.0.2", remote_interface: "can0", local_interface: "vcan0"}
]
```

That overlaps with [`nbpr_cannelloni`](../nbpr_cannelloni), which solves the
same problem with its own protocol and its own peer at both ends. Use this
one when the far end already runs socketcand.

`NBPR.Socketcand`'s docs carry the full runtime option schema for both.

Two defaults worth overriding:

- **`listen_interface`** is upstream's `eth0`, which is rarely a Nerves
  device's name for anything. It's both the bind address and where the UDP
  discovery beacon goes out; `no_beacon: true` turns the beacon off.
- **`interfaces`** is required here rather than defaulting to upstream's
  `vcan0`, which on a real device would quietly serve the wrong bus.

`-d`/`--daemon` isn't in the schema. It doesn't fork — it only redirects
logging to syslog — and leaving it off keeps the log lines on stdout where
MuonTrap captures them into the BEAM's logger.


## Build options

Set in your app's `config/target.exs`:

```elixir
config :nbpr_socketcand, build_opts: [libsocketcan: true]
```

| Option | Default | Effect |
|---|---|---|
| `libsocketcan` | `true` | Serve the protocol's interface-configuration commands — bitrate, controller mode, bus restart — instead of refusing them. |

Changing a build option changes the artefact cache key, so a build that
would otherwise download a prebuilt tarball falls back to a source build.

`libsocketcan` is on because a remote client that can't configure a bus can
only use one somebody else set up; the package depends on
`:nbpr_libsocketcan` so the `.so` is in the firmware either way. Buildroot's
`libconfig` option isn't exposed — it would need an `:nbpr_libconfig`
package, and everything in that config file is reachable through the daemon
module's options.


## Kernel requirements

socketcand opens raw CAN sockets, so it needs `CONFIG_CAN`, `CONFIG_CAN_RAW`
and a driver; the configuration commands additionally want `CONFIG_CAN_DEV`.
Stock Nerves systems enable none of them — see
[`nbpr_can_utils`](../nbpr_can_utils) for the full list and what to
ask a system maintainer for.

Source: <https://github.com/jimsynz/nbpr>.
