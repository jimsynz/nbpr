# nbpr_chrony

> NTP client and server (`chrony`) that can discipline the clock from a local GPS reference.

[`chrony`](https://chrony-project.org/) packaged for Nerves. Tracks the upstream Buildroot `chrony` package — this release wraps **4.8**.

Licence: GPL-2.0-only.


## This replaces `nerves_time`

Two daemons stepping the same system clock fight each other.
`nerves_time` ships in most Nerves projects by default (via
`nerves_pack`), so reach for this package only when you're deliberately
swapping it out — and remove `:nerves_time` from your deps when you do.

The usual reason to swap is a local reference clock: chrony can
discipline the system clock from GPS to microseconds, which SNTP over a
network can't approach.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_chrony, "~> 4.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Ship a config file via `rootfs_overlay/etc/chrony.conf`, then add the
daemon to your own supervision tree:

    children = [
      {NBPR.Chrony.Chronyd, config_file: "/etc/chrony.conf"}
    ]

See `NBPR.Chrony.Chronyd`'s `@moduledoc` for the full runtime options
schema.


## Taking time from gpsd

`:nbpr_gpsd` writes its time samples into two SHM segments, which chrony
reads as reference clocks:

    refclock SHM 0 refid GPS precision 1e-1 offset 0.9999 delay 0.2
    refclock SHM 1 refid PPS precision 1e-7

SHM 0 is the NMEA sentence time — only good to a few tens of milliseconds,
since it's timestamped whenever the sentence finished arriving. The `offset`
compensates for that latency and is specific to your receiver and baud rate;
`0.9999` is upstream's placeholder, deliberately too large to leave in
production. Measure yours against a known-good source.

SHM 1 is the PPS edge, and where the microseconds come from. The explicit
`precision` matters — chronyd doesn't read it out of the SHM structure, so
without it the PPS samples get weighted no better than the NMEA ones. It
needs gpsd built with `pps: true`, a `CONFIG_PPS` kernel, and a wired PPS
line.

Run gpsd with `nowait: true` (the default) or the samples stop whenever no
client is connected.


## Known gap: libcap

Buildroot's chrony `select`s libcap, so `chronyd` links `libcap.so.2`.
Nothing in a stock Nerves system provides that soname, and an nbpr
artefact only carries its own Buildroot files-list — so `mix firmware`'s
shared-library check will report `libcap.so.2` as unresolved. There is no
`:nbpr_libcap` package yet; adding one is the fix.

Source: <https://github.com/jimsynz/nbpr>.
