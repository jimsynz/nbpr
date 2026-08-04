defmodule NBPR.Chrony do
  @moduledoc """
  NBPR package for [`chrony`](https://chrony-project.org/) — an NTP
  implementation built for machines that spend time offline, boot without a
  working clock, or take their time from a local reference such as a GPS.

  Adds `chronyd` to the rootfs at `/usr/sbin/chronyd` and `chronyc` at
  `/usr/bin/chronyc`. Generates `NBPR.Chrony.Chronyd` — a MuonTrap-supervised
  GenServer the user adds to their own supervision tree:

      children = [
        {NBPR.Chrony.Chronyd, config_file: "/etc/chrony.conf"}
      ]

  Ship the config via `rootfs_overlay/etc/chrony.conf`. See
  `NBPR.Chrony.Chronyd` for the full runtime option schema.

  ## This replaces `nerves_time`, it doesn't complement it

  Two daemons stepping the same system clock fight each other. `nerves_time`
  is in most Nerves projects by default (via `nerves_pack`), so reach for this
  package only when you're deliberately swapping it out — and remove
  `:nerves_time` from your deps when you do. The usual reason to swap is a
  local reference clock: chrony can discipline the system clock from GPS to
  microseconds, which SNTP over a network can't approach.

  ## Taking time from gpsd

  `:nbpr_gpsd` writes its time samples into two SHM segments, which chrony
  reads as reference clocks:

      refclock SHM 0 refid GPS precision 1e-1 offset 0.9999 delay 0.2
      refclock SHM 1 refid PPS precision 1e-7

  SHM 0 is the NMEA sentence time — only good to a few tens of milliseconds,
  since it's timestamped whenever the sentence finished arriving. The
  `offset` compensates for that latency and is specific to your receiver and
  baud rate; `0.9999` is upstream's placeholder, deliberately too large to
  leave in production. Measure yours against a known-good source.

  SHM 1 is the PPS edge, and where the microseconds come from. The explicit
  `precision` matters — chronyd doesn't read it out of the SHM structure, so
  without it the PPS samples get weighted as though they were no better than
  the NMEA ones. It needs gpsd built with `pps: true`, a `CONFIG_PPS` kernel,
  and a wired PPS line; see `NBPR.PpsTools` for the kernel side.

  Run gpsd with `nowait: true` (the default) or the samples stop whenever no
  client is connected.

  ## Dependencies

  Buildroot's chrony `select`s libcap, so `chronyd` links `libcap.so.2`.
  Nothing in a stock Nerves system provides it and an nbpr artefact only
  carries its own files-list, so `mix firmware`'s shared-library check will
  flag it unless libcap is available — see this package's README for the
  current state of that.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "chrony",
    description: "NTP client and server that can discipline the clock from a local GPS reference",
    homepage: "https://chrony-project.org/",
    build_opts: [
      debug_logging: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_CHRONY_DEBUG_LOGGING",
        doc:
          "Compile in the debug logging paths, so `-d`/`log_level` can emit them. Without this the code isn't built and the verbose levels do nothing."
      ]
    ],
    daemons: [
      chronyd: [
        path: "/usr/sbin/chronyd",
        opts: [
          config_file: [
            type: :string,
            required: true,
            flag: "-f",
            doc:
              "Path to `chrony.conf`. Ship it via `rootfs_overlay/etc/chrony.conf` — chronyd's compiled-in default path doesn't exist on a Nerves rootfs."
          ],
          foreground: [
            type: :boolean,
            default: true,
            flag: "-n",
            doc:
              "Required `true` for MuonTrap supervision. Disabling lets chronyd detach and the GenServer loses the process it's tracking."
          ],
          set_clock_from_driftfile: [
            type: :boolean,
            default: false,
            flag: "-s",
            doc:
              "Set the clock from the driftfile (or RTC) at startup. Useful on a board with no RTC, where the clock starts at the epoch and a large initial step is expected rather than alarming."
          ],
          reload_sample_history: [
            type: :boolean,
            default: false,
            flag: "-r",
            doc:
              "Reload measurement histories saved by a previous run, then delete them. Only meaningful if `dumpdir` in the config points somewhere that survives a restart."
          ],
          no_clock_control: [
            type: :boolean,
            default: false,
            flag: "-x",
            doc:
              "Monitor and report offsets but never touch the system clock. Use to observe what chrony would do before handing it the clock."
          ],
          lock_memory: [
            type: :boolean,
            default: false,
            flag: "-m",
            doc: "Lock chronyd into RAM so it's never paged out, keeping its timing jitter low."
          ],
          ipv4_only: [
            type: :boolean,
            default: false,
            flag: "-4",
            doc: "Resolve names and open sockets over IPv4 only."
          ],
          ipv6_only: [
            type: :boolean,
            default: false,
            flag: "-6",
            doc: "Resolve names and open sockets over IPv6 only."
          ],
          log_level: [
            type: :integer,
            flag: "-L",
            doc:
              "Minimum severity to log, from `-1` (debug) to `3` (fatal). Unset leaves chronyd at its default of `0`. Levels below `0` need `debug_logging: true` at build time."
          ],
          priority: [
            type: :integer,
            flag: "-P",
            doc:
              "Real-time (SCHED_FIFO) scheduler priority, `0`–`100`. Unset leaves chronyd at normal scheduling."
          ]
        ]
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
