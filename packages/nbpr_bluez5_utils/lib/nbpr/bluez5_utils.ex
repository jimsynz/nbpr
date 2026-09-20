defmodule NBPR.Bluez5Utils do
  @moduledoc """
  NBPR package for [`bluez5_utils`](http://www.bluez.org) — the Linux Bluetooth
  stack.

  Adds `bluetoothd` to the rootfs at `/usr/libexec/bluetooth/bluetoothd`, and the
  `libbluetooth` shared library. Generates `NBPR.Bluez5Utils.Bluetoothd` — a
  MuonTrap-supervised GenServer you add to your own supervision tree:

      children = [
        {NBPR.Dbus.DbusDaemon, config_file: "/etc/dbus-1/system.conf"},
        {NBPR.Bluez5Utils.Bluetoothd, []}
      ]

  **The bus comes first.** `bluetoothd` claims `org.bluez` on the system bus as it
  starts, and it exits when there is no bus to claim it on. See `NBPR.Dbus`.

  ## The kernel side is not in this package, and it is where the time goes

  A rootfs with `bluetoothd` in it and a kernel with no Bluetooth gives you a
  daemon that starts, logs nothing unusual, and finds no adapter. Check
  `/sys/class/bluetooth` before you look anywhere else: empty means the kernel,
  not this package.

  The config a Raspberry Pi needs:

      CONFIG_BT=y
      CONFIG_BT_BREDR=y
      CONFIG_BT_LE=y
      CONFIG_BT_HCIUART=y
      CONFIG_BT_HCIUART_SERDEV=y
      CONFIG_BT_HCIUART_BCM=y
      CONFIG_SERIAL_DEV_BUS=y
      CONFIG_SERIAL_DEV_CTRL_TTYPORT=y

  **`CONFIG_BT_HCIUART_SERDEV` depends on `SERIAL_DEV_BUS` and does not select
  it.** A fragment that leaves the last two out builds without a word of
  complaint, `make olddefconfig` quietly puts `BT_HCIUART_SERDEV` back to `n`, and
  the board boots with an empty `/sys/class/bluetooth` and no line of Bluetooth in
  `dmesg`.

  A Pi also needs its firmware blob. `rpi-distro-bluez-firmware` installs the
  `.hcd` files with the per-board symlinks, so the `btbcm` driver picks the right
  one from the compatible string of the device tree. That is a system-level
  package, not one of these, because the kernel loads it before any of the rootfs
  is your code.

  ## What a Nerves rootfs does not give it

  **Somewhere to keep the pairing keys.** `bluetoothd` writes them under
  `/var/lib/bluetooth`, which is read-only squashfs. Symlink that path from
  `rootfs_overlay` to somewhere on the writable data partition, and check where
  that partition mounts on your system: it is `/data` on most of them and `/root`
  on some.

  A device that cannot write there pairs, plays, and then asks for the PIN again
  at the next boot.

  ## What you talk to it with

  D-Bus, and nothing else. `bluetoothctl` is there if you build `client: true`,
  and a person with a serial console can pair by hand with it, but a program pairs
  over the bus.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "bluez5_utils",
    description: "BlueZ utils",
    homepage: "http://www.bluez.org",
    build_opts: [
      audio: [
        type: :boolean,
        default: true,
        br_flag: "BR2_PACKAGE_BLUEZ5_UTILS_PLUGINS_AUDIO",
        doc:
          "Build the A2DP and AVRCP plugins. Needed by anything that sends audio to a speaker or takes audio from a telephone. See `NBPR.BluezAlsa`."
      ],
      client: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_BLUEZ5_UTILS_CLIENT",
        doc:
          "Build `bluetoothctl`. It pulls in readline, and it is worth the room on a device you can get a console on: it is how you find out whether a pairing problem is yours or BlueZ's."
      ],
      tools: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_BLUEZ5_UTILS_TOOLS",
        doc: "Build the command-line tools, such as `hcitool` and `sdptool`."
      ],
      monitor: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_BLUEZ5_UTILS_MONITOR",
        doc:
          "Build `btmon`, which prints the HCI traffic. The tool to reach for when a pairing fails and the log says nothing."
      ],
      obex: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_BLUEZ5_UTILS_OBEX",
        doc: "Build `obexd`, for transferring files. An audio device needs none of it."
      ],
      hid: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_BLUEZ5_UTILS_PLUGINS_HID",
        doc: "Build the plugin for keyboards, mice and game controllers."
      ],
      experimental: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_BLUEZ5_UTILS_EXPERIMENTAL",
        doc:
          "Build the interfaces that upstream has not settled. Some battery reporting over BLE lives here."
      ]
    ],
    daemons: [
      bluetoothd: [
        path: "/usr/libexec/bluetooth/bluetoothd",
        opts: [
          foreground: [
            type: :boolean,
            default: true,
            flag: "--nodetach",
            doc:
              "Required `true` for MuonTrap supervision. Disabling lets the daemon detach and the GenServer loses the process it is tracking."
          ],
          config_file: [
            type: :string,
            flag: "--configfile",
            doc:
              "Path to `main.conf`. Unset leaves the compiled-in default of `/etc/bluetooth/main.conf`, which a Nerves rootfs has only if you ship one. The defaults are reasonable for an audio device."
          ],
          experimental: [
            type: :boolean,
            default: false,
            flag: "--experimental",
            doc:
              "Turn on the experimental interfaces at runtime. They also have to be built: see the `:experimental` build option."
          ],
          compat: [
            type: :boolean,
            default: false,
            flag: "--compat",
            doc: "Provide the deprecated command interfaces that the old tools use."
          ],
          debug: [
            type: :string,
            flag: "--debug",
            doc:
              "Comma-separated globs of source files to log from, such as `src/adapter.c`. Unset logs nothing extra."
          ],
          plugin: [
            type: :string,
            flag: "--plugin",
            doc:
              "Comma-separated list of plugins to load, instead of all of them. `a2dp,avrcp` is what an audio device needs."
          ],
          noplugin: [
            type: :string,
            flag: "--noplugin",
            doc: "Comma-separated list of plugins not to load."
          ]
        ]
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
