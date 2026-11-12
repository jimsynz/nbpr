# nbpr_can_utils

> Userspace tools for Linux SocketCAN.

[`can-utils`](https://github.com/linux-can/can-utils) packaged for Nerves. Tracks the upstream Buildroot `can-utils` package — this release wraps **2025.01**.

Licences: BSD-3-Clause, GPL-2.0-only.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_can_utils, "~> 2025.0", organization: "nbpr"}

can-utils versions by calendar year, so the Hex major is the year and a
requirement written this way stops matching when upstream cuts its next
annual release. Widen it deliberately when that happens rather than
assuming a dead `~>` is upstream going quiet.

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://nbpr.hexdocs.pm/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.


## What you get

35 binaries under `/usr/bin/`, plus `libisobusfs.so` under `/usr/lib/`. None of
them is a daemon in NBPR's sense, so the package generates no supervised
module — these are tools you run from a console or `System.cmd/3`.

| Group | Binaries | Kernel symbol |
|-------|----------|---------------|
| Raw CAN | `candump`, `cansend`, `cangen`, `canplayer`, `canlogserver`, `cansniffer`, `canbusload`, `cansequence`, `canfdtest` | `CONFIG_CAN_RAW` |
| Log conversion | `asc2log`, `log2asc`, `log2long` | — |
| Broadcast manager | `bcmserver` | `CONFIG_CAN_BCM` |
| Gateway | `cangw` | `CONFIG_CAN_GW` |
| ISO-TP (ISO 15765-2) | `isotpsend`, `isotprecv`, `isotpdump`, `isotpsniffer`, `isotpperf`, `isotptun`, `isotpserver` | `CONFIG_CAN_ISOTP` |
| SAE J1939 | `j1939acd`, `j1939cat`, `j1939spy`, `j1939sr`, `testj1939`, `j1939-timedate-cli`, `j1939-timedate-srv` | `CONFIG_CAN_J1939` |
| ISOBUS-FS (ISO 11783-13) | `isobusfs-srv`, `isobusfs-cli` | `CONFIG_CAN_J1939` |
| Serial-line CAN | `slcand`, `slcan_attach`, `slcanpty` | `CONFIG_CAN_SLCAN` |
| Bit timing and debug | `can-calc-bit-timing`, `mcp251xfd-dump` | — |


## Kernel requirements

These are userspace tools for a kernel subsystem, and shipping them doesn't
enable that subsystem. **Stock Nerves systems don't enable `CONFIG_CAN`** —
there's no `can0` to configure and no `PF_CAN` to bind until the system
maintainer turns it on (or you build a fork). The minimum is `CONFIG_CAN`, `CONFIG_CAN_RAW`, `CONFIG_CAN_DEV`, and a controller
driver: `CONFIG_CAN_MCP251X` for the MCP2515 SPI HATs,
`CONFIG_CAN_MCP251XFD` for MCP2517FD/MCP2518FD, `CONFIG_CAN_FLEXCAN` on
i.MX, `CONFIG_CAN_C_CAN_PLATFORM` for the BeagleBone's D_CAN. Add
`CONFIG_CAN_VCAN` as well — a virtual interface is how you exercise these
tools with no hardware attached.

Each protocol family in the table above is its own symbol, and the matching
tools fail at `socket(2)` with `EPROTONOSUPPORT` when it's missing rather
than anywhere more informative.

An SPI CAN HAT on a Raspberry Pi also needs a device-tree overlay —
`dtoverlay=mcp2515-can0,oscillator=16000000,interrupt=25` or similar in
`config.txt`, matching the board's crystal and interrupt line. Like the
kernel config, that lives in the Nerves system and is outside NBPR's remit.


## Bringing an interface up

No extra package needed. Nerves builds busybox with
`CONFIG_FEATURE_IP_LINK_CAN`, so the stock rootfs already configures CAN
interfaces and `iproute2` isn't required:

    System.cmd("ip", ~w[link set can0 type can bitrate 500000])
    System.cmd("ip", ~w[link set can0 up])

Source: <https://github.com/jimsynz/nbpr>.
