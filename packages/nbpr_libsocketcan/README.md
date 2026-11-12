# nbpr_libsocketcan

> C library for configuring SocketCAN interfaces over netlink.

[`libsocketcan`](http://git.pengutronix.de/?p=tools/libsocketcan.git;a=summary) packaged for Nerves. Tracks the upstream Buildroot `libsocketcan` package — this release wraps **0.0.12**.

Licence: LGPL-2.1-or-later.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_libsocketcan, "~> 0.0.12", organization: "nbpr"}

libsocketcan has been `0.0.x` since 2012, so the whole patch component is
the series — `~> 0.1` would match nothing.

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.


## What you get

The shared library and nothing else — no binaries. It wraps the rtnetlink
calls that set and read a CAN interface's configuration (`can_set_bitrate`,
`can_set_bittiming`, `can_set_ctrlmode`, `can_do_start`, `can_get_state`,
`can_get_berr_counter` and friends): the C API for what `ip link set <dev>
type can ...` does from a shell.

**There is no Elixir binding here, and nothing else in NBPR links it
today.** Reach for it when a NIF or port program of yours wants to configure
a CAN interface and read its error counters without shelling out — the
artefact carries `libsocketcan.h`, `can_netlink.h` and a `.pc` file in its
staging slice, so it's linkable at firmware-build time.
It is also what `socketcand` builds against for its bitrate and
controller-mode commands, should that package land.

Reading and writing CAN *frames* from Elixir needs neither this nor
`:nbpr_can_utils` — that's an ordinary `AF_CAN` socket, and the kernel is
the whole interface.


## Kernel requirements

Every call here is netlink against a CAN netdev, so `CONFIG_CAN` and
`CONFIG_CAN_DEV` have to be on. Stock Nerves systems enable neither — see
[`nbpr_can_utils`](../nbpr_can_utils) for the full list and what
to ask a system maintainer for.

Source: <https://github.com/jimsynz/nbpr>.
