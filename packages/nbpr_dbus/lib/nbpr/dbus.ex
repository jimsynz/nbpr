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

  ## Why you would want this on a Nerves device

  On a desktop D-Bus is how everything talks to everything. On an appliance there
  is usually one reason: **BlueZ speaks D-Bus and nothing else.** `bluetoothd`
  offers no socket protocol and no library API — a program that wants to pair a
  device or route audio talks to the system bus. See `NBPR.Bluez5Utils`.

  If you have no such daemon, you do not want this package.

  ## The three things a Nerves rootfs does not give it

  **A configuration file.** Buildroot installs `/usr/share/dbus-1/system.conf`,
  and `dbus-daemon` looks for `/etc/dbus-1/system.conf`. Ship your own through
  `rootfs_overlay/etc/dbus-1/`, or name the installed one in `config_file`.

  **A socket directory.** The system bus listens on
  `unix:path=/run/dbus/system_bus_socket`, and `/run` on a Nerves rootfs holds
  whatever the boot put there. Make the directory before the daemon starts:
  `File.mkdir_p!("/run/dbus")`.

  **A machine id.** `dbus-daemon` reads `/etc/machine-id`, or
  `/var/lib/dbus/machine-id`, and refuses to start without one. Both paths are
  read-only squashfs on Nerves, so write the id somewhere that is not and symlink
  to it from the overlay. Any 32 hex digits will do: the bus uses it to tell one
  machine from another and nothing else.

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
              "Path to the bus configuration. Buildroot installs `/usr/share/dbus-1/system.conf`, and the compiled-in default of `/etc/dbus-1/system.conf` does not exist on a Nerves rootfs unless you put it there."
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
