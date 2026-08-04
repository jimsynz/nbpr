# nbpr_pps_tools

> Userspace utilities for the Linux PPS (pulse-per-second) API.

[`pps-tools`](https://github.com/redlab-i/pps-tools/) packaged for Nerves. Tracks the upstream Buildroot `pps-tools` package — this release wraps **1.0.3**.

Licence: GPL-2.0-or-later.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_pps_tools, "~> 1.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.


## What you get

Five binaries under `/usr/bin/`:

| Binary     | Purpose |
|------------|---------|
| `ppsfind`  | resolve a PPS source name to its `/dev/pps*` device |
| `ppstest`  | print timestamps as pulses arrive — the first thing to run when checking whether a PPS line is wired up |
| `ppsctl`   | query and set a source's fetch/capture parameters |
| `ppswatch` | long-running monitor reporting jitter and offset |
| `ppsldisc` | attach the PPS line discipline to a serial port, turning a GPS receiver's PPS-on-DCD into a `/dev/pps*` device |

It also installs `sys/timepps.h` into the sysroot. That header is what
`:nbpr_gpsd`'s `pps: true` build option is after — Buildroot gates gpsd's
`HAVE_SYS_TIMEPPS_H` code path and its `ppscheck` client on
`BR2_PACKAGE_PPS_TOOLS`.


## Kernel requirements

These are userspace tools for a kernel facility, and shipping them doesn't
enable that facility. The active Nerves system's kernel needs `CONFIG_PPS`
plus at least one client:

- `CONFIG_PPS_CLIENT_LDISC` — PPS via a serial port's DCD line, paired with
  `ppsldisc`. The usual route for a UART-attached GPS.
- `CONFIG_PPS_CLIENT_GPIO` — PPS via a GPIO, paired with a `pps-gpio`
  device-tree overlay. The usual route for a Raspberry Pi GPS HAT.

Stock Nerves systems don't enable `CONFIG_PPS`, so `/dev/pps*` won't exist
until the system maintainer turns it on (or you build a fork). Kernel
configuration is outside NBPR's remit — `ppstest` reporting no such device
is the expected result on an unmodified system.

Source: <https://github.com/jimsynz/nbpr>.
