defmodule NBPR.Gpsd do
  @moduledoc """
  NBPR package for [`gpsd`](https://gpsd.gitlab.io/gpsd) — the service daemon
  that owns your GPS/GNSS or AIS receiver and republishes its fixes over a
  JSON protocol on TCP 2947.

  Adds `gpsd` to the rootfs at `/usr/sbin/gpsd`, the client binaries under
  `/usr/bin/`, and `libgps` for anything that wants to link it. Generates
  `NBPR.Gpsd.Gpsd` — a MuonTrap-supervised GenServer the user adds to their
  own supervision tree:

      children = [
        {NBPR.Gpsd.Gpsd, devices: ["/dev/ttyAMA0"]}
      ]

  See `NBPR.Gpsd.Gpsd` for the full runtime option schema.

  ## Which receivers work out of the box

  gpsd compiles most protocol drivers unconditionally, and Buildroot only
  exposes toggles for the rest — so with no build options set you already get
  **NMEA0183, u-blox (UBX), MTK3301, NTRIP and RTCM v2/v3**. That covers
  every u-blox module and effectively all generic NMEA receivers, USB pucks
  included.

  The 22 remaining drivers are vendor-specific binary protocols that
  Buildroot defaults off, one build option each below. Turning any of them on
  changes the artefact cache key, so a build that would otherwise download a
  prebuilt tarball falls back to a source build.

  ## Configuring a u-blox receiver

  gpsd's own `gpsctl` ships with the clients and handles the common cases —
  setting the baud rate, switching between NMEA and UBX binary mode, and
  dumping the receiver's version and configuration:

      System.cmd("gpsctl", ["-f", "-s", "115200", "/dev/ttyAMA0"])

  `ubxtool`, gpsd's lower-level UBX tool, is **not** included: upstream ships
  it as a Python script, so it would drag `python3` and `pyserial` into the
  firmware — and because an nbpr artefact only carries its own Buildroot
  files-list, the interpreter wouldn't come with it and the shebang would
  dangle. For UBX message-level work, talk to the port directly from Elixir
  (`Circuits.UART`) or drive gpsd's JSON protocol on 2947.

  ## Client binaries

  With `clients: true` (the default), under `/usr/bin/`: `gpsctl`,
  `gpsdecode`, `gpspipe`, `gps2udp`, `gpsrinex`, `gpssnmp`, `gpxlogger`,
  `lcdgps`, `ntpshmmon` and `ppscheck`. `gpsdctl`, which adds and removes
  devices over the daemon's control socket, installs alongside the daemon in
  `/usr/sbin/`.

  The interactive `cgps` and `gpsmon` need curses. On every Raspberry Pi
  system you get them for free, because the system's `nerves_defconfig`
  enables `alsa-utils`, whose Kconfig `select`s ncurses — and a `select` wins
  over `ncurses: false`, so there's no turning them off there either. On
  `bbb`, `x86_64` and `qemu_aarch64` nothing pulls ncurses in, so set
  `ncurses: true` and add `:nbpr_ncurses` for the library.

  ## Not exposed, and why

    * **Python support** (`BR2_PACKAGE_GPSD_PYTHON`) — as above; would need an
      `:nbpr_python3` package to be useful.
    * **Privilege revocation** (`BR2_PACKAGE_GPSD_USER`/`_GROUP`) — Nerves runs
      the BEAM as root and dropping to `nobody` costs gpsd its device access.
    * **`BR2_PACKAGE_GPSD_DEVICES`** — only ever substituted into Buildroot's
      SysV init script, which a Nerves system (`BR2_INIT_NONE`) never installs.
      Pass devices to the daemon module instead.
    * **`BR2_PACKAGE_GPSD_MAX_CLIENT`/`MAX_DEV`** — Buildroot models each as a
      boolean gating a separate value symbol, which doesn't map onto a single
      build option. gpsd's compiled-in defaults are generous enough.
    * **`BR2_PACKAGE_GPSD_PROFILING`** — a development-only gprof build, and
      Buildroot forbids it on aarch64 anyway.

  ## USB receivers

  A USB GPS puck shows up as `/dev/ttyUSB*` through the kernel's usbserial
  drivers, which is all gpsd needs. Buildroot's libusb path is only for
  Garmin's non-serial USB protocol, so it stays off.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "gpsd",
    description: "GPS/GNSS and AIS receiver monitoring daemon, client tools, and libgps",
    homepage: "https://gpsd.gitlab.io/gpsd",
    build_opts: [
      clients: [
        type: :boolean,
        default: true,
        br_flag: "BR2_PACKAGE_GPSD_CLIENTS",
        doc:
          "Build the client programs (`gpsctl`, `gpspipe`, `gpsdecode`, `gpsdctl`, ...) alongside the daemon."
      ],
      client_debug: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_CLIENT_DEBUG",
        doc: "Compile debug-level tracing into the client library."
      ],
      ncurses: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_NCURSES",
        doc:
          "Build the curses clients `cgps` and `gpsmon`, and add `:nbpr_ncurses` to your deps for the library — this only sets Buildroot's ncurses symbol. Needed on `bbb`, `x86_64` and `qemu_aarch64`; a no-op on the Raspberry Pi systems, where `alsa-utils` already `select`s ncurses and those clients build either way."
      ],
      pps: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_PPS_TOOLS",
        doc:
          "Compile gpsd's `HAVE_SYS_TIMEPPS_H` timing paths, which need `sys/timepps.h` from Buildroot's pps-tools. The `ppscheck` client builds either way, but only reports real pulse timings with this on. Pair with `:nbpr_pps_tools` for the userspace utilities, and note the kernel needs `CONFIG_PPS` — see `NBPR.PpsTools`."
      ],
      squelch: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_SQUELCH",
        doc:
          "Compile out `gpsd_report` and `gpsd_hexdump` to save CPU, at the cost of all diagnostic logging."
      ],
      aivdm: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_AIVDM",
        doc: "AIS support (AIVDM/AIVDO sentences) for marine vessel tracking."
      ],
      ashtech: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_ASHTECH",
        doc: "Ashtech binary protocol support."
      ],
      earthmate: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_EARTHMATE",
        doc: "DeLorme EarthMate Zodiac protocol support."
      ],
      evermore: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_EVERMORE",
        doc: "EverMore binary protocol support."
      ],
      fury: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_FURY",
        doc: "Jackson Labs Fury and Firefly GPSDO support."
      ],
      fv18: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_FV18",
        doc: "San Jose Navigation FV-18 protocol support."
      ],
      garmin: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_GARMIN",
        doc: "Garmin binary protocol support via the kernel driver."
      ],
      garmin_simple_text: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_GARMIN_SIMPLE_TXT",
        doc: "Garmin Simple Text protocol support."
      ],
      geostar: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_GEOSTAR",
        doc: "Geostar binary protocol support."
      ],
      gpsclock: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_GPSCLOCK",
        doc: "GPSClock protocol support."
      ],
      greis: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_GREIS",
        doc: "Javad GREIS protocol support."
      ],
      isync: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_ISYNC",
        doc: "Spectratime iSync LNRClok/GRCLOK protocol support."
      ],
      itrax: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_ITRAX",
        doc: "iTrax protocol support."
      ],
      navcom: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_NAVCOM",
        doc: "Navcom binary protocol support."
      ],
      nmea2000: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_NMEA2000",
        doc:
          "NMEA2000/CAN protocol support. Buildroot's Kconfig `select`s the Navcom and AIVDM drivers, which wins over an explicit `navcom: false`/`aivdm: false` here."
      ],
      oncore: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_ONCORE",
        doc: "Motorola OnCore protocol support."
      ],
      sirf: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_SIRF",
        doc: "SiRF binary protocol support."
      ],
      skytraq: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_SKYTRAQ",
        doc: "Skytraq binary protocol support."
      ],
      superstar2: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_SUPERSTAR2",
        doc: "Novatel SuperStarII binary protocol support."
      ],
      trimble_tsip: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_TRIMBLE_TSIP",
        doc: "Trimble TSIP protocol support."
      ],
      tripmate: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_TRIPMATE",
        doc: "DeLorme TripMate protocol support."
      ],
      true_north: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_GPSD_TRUE_NORTH",
        doc: "True North Technologies digital compass support."
      ]
    ],
    daemons: [
      gpsd: [
        path: "/usr/sbin/gpsd",
        argv_template: {__MODULE__, :argv, []},
        opts: [
          devices: [
            type: {:list, :string},
            required: true,
            doc:
              "Receivers to open, as positional arguments. Local serial devices (`/dev/ttyAMA0`, `/dev/ttyUSB0`), or remote feeds (`tcp://host:port`, `udp://host:port`, `gpsd://host`). Pass `[]` to start with none and add them later over the control socket with `gpsdctl`."
          ],
          foreground: [
            type: :boolean,
            default: true,
            flag: "-N",
            doc:
              "Required `true` for MuonTrap supervision — gpsd otherwise forks into the background and the GenServer loses the process it's tracking."
          ],
          nowait: [
            type: :boolean,
            default: true,
            flag: "-n",
            doc:
              "Poll the receiver without waiting for a client to connect. Defaults on (gpsd defaults off) because a Nerves app usually wants a fix ready on demand, and because feeding chrony's SHM refclock depends on it."
          ],
          listen_any: [
            type: :boolean,
            default: false,
            flag: "-G",
            doc:
              "Listen on all addresses rather than loopback only. Exposes the receiver to anything that can reach the device on `port`."
          ],
          port: [
            type: :integer,
            default: 2947,
            flag: "-S",
            doc: "TCP port to serve the JSON protocol on."
          ],
          readonly: [
            type: :boolean,
            default: false,
            flag: "-b",
            doc:
              "Broken-device-safety mode: never write to the receiver. Disables autobauding and mode switching, but avoids wedging the handful of devices that lock up when probed."
          ],
          passive: [
            type: :boolean,
            default: false,
            flag: "-p",
            doc: "Don't auto-configure the receiver — leave whatever mode and rate it booted in."
          ],
          badtime: [
            type: :boolean,
            default: false,
            flag: "-r",
            doc:
              "Use the receiver's time even without a position fix. Useful when the device has no RTC and needs the clock set before it can get a fix."
          ],
          debug: [
            type: :integer,
            flag: "-D",
            doc: "Debug verbosity level. Unset leaves gpsd at its default of 0."
          ],
          speed: [
            type: :integer,
            flag: "-s",
            doc: "Fix the serial port speed instead of autobauding, e.g. `9600` or `115200`."
          ],
          framing: [
            type: :string,
            flag: "-f",
            doc: "Fix the serial framing rather than detecting it, e.g. `\"8N1\"`."
          ],
          sockfile: [
            type: :string,
            flag: "-F",
            doc:
              "Path to the control socket, which `gpsdctl` uses to add and remove devices at runtime. Put it on the writable `/run` tmpfs, e.g. `\"/run/gpsd.sock\"`."
          ]
        ]
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]

  @doc """
  Builds gpsd's argv, appending `:devices` as positional arguments.

  gpsd takes its receivers positionally rather than behind a flag, which
  `NBPR.BrPackage.default_argv/2` can't express on its own — so this pops
  `:devices` off, delegates the flagged options, and appends the devices last.
  """
  @spec argv(keyword(), %{atom() => String.t()}) :: [String.t()]
  def argv(opts, opt_flags) do
    {devices, flagged} = Keyword.pop!(opts, :devices)

    NBPR.BrPackage.default_argv(flagged, opt_flags) ++ devices
  end
end
