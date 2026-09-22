defmodule NBPR.Dbus do
  @moduledoc """
  NBPR package for [`dbus`](https://www.freedesktop.org/wiki/Software/dbus) — the
  D-Bus message bus.

  Adds `dbus-daemon` to the rootfs at `/usr/bin/dbus-daemon`, plus `libdbus-1.so`
  and the command-line tools. Generates `NBPR.Dbus.DbusDaemon` — a
  MuonTrap-supervised GenServer you add to your own supervision tree:

      children = [
        {NBPR.Dbus.DbusDaemon, config_file: "/etc/dbus-1/system.conf"}
      ]

  **That path is a file you ship, not one this package installs** — see below,
  because the `system.conf` in this package's priv that shares the name is a
  stub that starts no bus.

  ## Why you would want this on a Nerves device

  On a desktop D-Bus is how everything talks to everything. On an appliance there
  is usually one reason: **BlueZ speaks D-Bus and nothing else.** `bluetoothd`
  offers no socket protocol and no library API — a program that wants to pair a
  device or route audio talks to the system bus. See `NBPR.Bluez5Utils`.

  If you have no such daemon, you do not want this package.

  ## Two files are called `system.conf` and only one of them is a bus

  This package ships both of the files D-Bus installs under that name, and the
  difference between them is the difference between a bus that starts and one
  that does not.

  **`usr/share/dbus-1/system.conf` is the configuration.** It carries the
  `<type>`, the `<listen>` address, the `<user>` and the default policy, and it
  is what `dbus-daemon --system` means: `dbus` compiles `DBUS_SYSTEM_CONFIG_FILE`
  as `$(datadir)/dbus-1/system.conf`, so the built-in system configuration is the
  `/usr/share` path and not the `/etc` one.

  **`etc/dbus-1/system.conf` is a stub, and at 1.14.10 not even an including
  one.** It is `<busconfig></busconfig>` under a comment saying the file is no
  longer required and may be removed — D-Bus keeps installing it so that a
  sysadmin's older `/etc` edits still get picked up, by the `<include>` near the
  bottom of the real file. Hand it to `--config-file` and `dbus-daemon` parses a
  bus with no type, no address and no policy, and exits without listening.

  So: **base your configuration on the `/usr/share` one.** It is in this
  package's priv, at

      Path.join(:code.priv_dir(:nbpr_dbus), "usr/share/dbus-1/system.conf")

  ## The three things a Nerves rootfs does not give it

  **A configuration file that fits.** The shipped `/usr/share` one does not run
  as it stands: it asks for `<user>dbus</user>`, and Nerves has no `dbus` user.
  Copy it into `rootfs_overlay/etc/dbus-1/system.conf`, change the `<user>` to
  `root`, drop the `<servicehelper>` you have no activation for, and name your
  copy in `config_file`. The `<fork/>` can stay — `foreground: true` passes
  `--nofork`, which overrides it. On an appliance where everything runs as root
  what survives is a few dozen lines, and it is honest about what the bus allows
  rather than inheriting a desktop's answer.

  **A socket directory.** The system bus listens on
  `unix:path=/run/dbus/system_bus_socket`, and `/run` on a Nerves rootfs holds
  whatever the boot put there. Make the directory before the daemon starts:
  `File.mkdir_p!("/run/dbus")`.

  **A machine id.** `dbus-daemon` reads `/etc/machine-id`, or
  `/var/lib/dbus/machine-id`, and refuses to start without one. Both paths are
  read-only squashfs on Nerves, so write the id somewhere that is not and symlink
  to it from the overlay. Any 32 hex digits will do: the bus uses it to tell one
  machine from another and nothing else.

  ## The policy of the bus, and where BlueZ's half of it goes

  `system.conf` denies what it does not allow, and it picks up the rest of the
  policy from `<includedir>system.d</includedir>` — **a relative path, resolved
  against the directory of the file that named it.** BlueZ ships the fragment
  that lets a process own `org.bluez`, and on a Buildroot rootfs it and the bus
  configuration both land under `/usr/share/dbus-1` and find each other.

  They do not here: each package lands under its own priv directory, so that
  relative include resolves inside `nbpr_dbus`'s priv and never sees the
  `usr/share/dbus-1/system.d/bluetooth.conf` in `nbpr_bluez5_utils`'s. A device
  that starts the bus this way gets `org.freedesktop.DBus.Error.AccessDenied`
  the moment `bluetoothd` tries to claim its name.

  The `/usr/share` configuration also carries
  `<includedir>/etc/dbus-1/system.d</includedir>`, and that one is absolute and
  resolves in the rootfs. Copy the fragments you need — BlueZ's from
  `NBPR.Bluez5Utils`, BlueALSA's from `NBPR.BluezAlsa` — into
  `rootfs_overlay/etc/dbus-1/system.d/`, or write the policy straight into the
  `system.conf` you ship.

  ## Who starts it

  Nothing in this package. Buildroot ships an init script, and a Nerves rootfs
  runs no init system, so the daemon module above is the whole of the answer. A
  library that manages BlueZ for you may start the bus itself — check before you
  start two.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "dbus",
    description: "The D-Bus message bus system.",
    homepage: "https://www.freedesktop.org/wiki/Software/dbus",
    daemons: [
      dbus_daemon: [
        path: "/usr/bin/dbus-daemon",
        opts: [
          config_file: [
            type: :string,
            required: true,
            flag: "--config-file",
            doc:
              "Path to the bus configuration, in the rootfs rather than in this package's priv — ship it through `rootfs_overlay/etc/dbus-1/system.conf`. Base it on the `usr/share/dbus-1/system.conf` in priv, which is the real configuration; the `etc/dbus-1/system.conf` next to it is D-Bus's legacy stub and starts no bus. The compiled-in default, `/usr/share/dbus-1/system.conf`, is a rootfs path an NBPR package never writes to."
          ],
          foreground: [
            type: :boolean,
            default: true,
            flag: "--nofork",
            doc:
              "Required `true` for MuonTrap supervision. Disabling lets the daemon fork and the GenServer loses the process it is tracking."
          ],
          print_address: [
            type: :boolean,
            default: false,
            flag: "--print-address",
            doc:
              "Write the address of the bus to standard output once it is listening. Useful when the address comes from the configuration rather than from you."
          ],
          syslog: [
            type: :boolean,
            default: false,
            flag: "--syslog",
            doc:
              "Send messages to syslog as well as to standard error. A Nerves device usually wants the default, because MuonTrap already carries standard error into the logger."
          ]
        ]
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
