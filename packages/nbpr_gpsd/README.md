# nbpr_gpsd

> GPS/GNSS and AIS receiver monitoring daemon (`gpsd`), client tools, and libgps.

[`gpsd`](https://gpsd.gitlab.io/gpsd) packaged for Nerves. Tracks the upstream Buildroot `gpsd` package — this release wraps **3.27.5**.

Licence: BSD-2-Clause.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_gpsd, "~> 3.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Add the daemon to your own supervision tree:

    children = [
      {NBPR.Gpsd.Gpsd, devices: ["/dev/ttyAMA0"]}
    ]

Then query it over the JSON protocol on `localhost:2947`, or shell out
to the client tools:

    {json, 0} = System.cmd("gpspipe", ["-w", "-n", "5"])

See `NBPR.Gpsd.Gpsd`'s `@moduledoc` for the full runtime options schema.


## Receiver support

With no build options set you get **NMEA0183, u-blox (UBX), MTK3301,
NTRIP and RTCM v2/v3** — gpsd compiles those unconditionally. That covers
every u-blox module and effectively all generic NMEA receivers, USB pucks
included.

Buildroot exposes toggles for 22 further vendor binary protocols
(Trimble TSIP, SiRF, Skytraq, Garmin, AIS/AIVDM, NMEA2000, ...), all
defaulting off. Enable what you need in `config/target.exs`:

    config :nbpr_gpsd, build_opts: [
      aivdm: true,
      trimble_tsip: true
    ]

Any non-default build option changes the artefact cache key, so the
build falls back from a prebuilt tarball to a source build.


## Configuring a u-blox receiver

gpsd's `gpsctl` handles baud rate, NMEA/UBX mode switching, and version
and configuration dumps:

    System.cmd("gpsctl", ["-f", "-s", "115200", "/dev/ttyAMA0"])

`ubxtool` is **not** included — upstream ships it as a Python script, so
it would need `python3` and `pyserial` in the firmware, and an nbpr
artefact only carries its own Buildroot files-list so the interpreter
wouldn't come with it. For UBX message-level work, drive the port from
Elixir with `Circuits.UART`, or use gpsd's JSON protocol.


## Client binaries

With `clients: true` (the default), under `/usr/bin/`: `gpsctl`,
`gpsdecode`, `gpspipe`, `gps2udp`, `gpsrinex`, `gpssnmp`, `gpxlogger`,
`lcdgps`, `ntpshmmon` and `ppscheck`. `gpsdctl`, which adds and removes
devices over the daemon's control socket, installs alongside the daemon in
`/usr/sbin/`.

The interactive `cgps` and `gpsmon` need curses. On every Raspberry Pi
system you get them for free — the system's `nerves_defconfig` enables
`alsa-utils`, whose Kconfig `select`s ncurses, and a `select` wins over
`ncurses: false` so there's no turning them off there either. On `bbb`,
`x86_64` and `qemu_aarch64` nothing pulls ncurses in, so set
`ncurses: true` and add `:nbpr_ncurses` for the library.


## Companion packages

- `:nbpr_pps_tools` — set `pps: true` for gpsd's `HAVE_SYS_TIMEPPS_H`
  timing paths, which is what makes `ppscheck` report real pulse timings.
  Needs a `CONFIG_PPS` kernel.
- `:nbpr_ncurses` — only on `bbb`, `x86_64` and `qemu_aarch64`; see above.
- `:nbpr_chrony` — discipline the system clock from this receiver via
  chrony's SHM refclock.

Source: <https://github.com/jimsynz/nbpr>.
