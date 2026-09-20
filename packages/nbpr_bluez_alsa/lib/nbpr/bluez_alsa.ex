defmodule NBPR.BluezAlsa do
  @moduledoc """
  NBPR package for [`bluez-alsa`](https://github.com/Arkq/bluez-alsa) — Bluetooth
  audio as an ALSA device.

  **This is the piece that makes a Bluetooth speaker look like a sound card.** It
  installs a userspace ALSA plugin, so a program that already writes to ALSA needs
  no Bluetooth code at all: it opens `bluealsa:DEV=<address>` where it used to open
  `hw:0,0`, and `aplay` and every other ALSA program work unchanged.

  Adds `bluealsad` at `/usr/bin/bluealsad`, the ALSA plugin at
  `/usr/lib/alsa-lib/libasound_module_pcm_bluealsa.so`, and `bluealsactl` and
  `bluealsa-aplay`. Generates `NBPR.BluezAlsa.Bluealsad` — a MuonTrap-supervised
  GenServer you add to your own supervision tree:

      children = [
        {NBPR.Dbus.DbusDaemon, config_file: "/etc/dbus-1/system.conf"},
        {NBPR.Bluez5Utils.Bluetoothd, []},
        {NBPR.BluezAlsa.Bluealsad, profiles: ["a2dp-source"]}
      ]

  The order is the order: the bus, then BlueZ, then this.

  ## Which end of the link you are

  **`a2dp-source` sends audio to a speaker**, and it is what a stereo or a phone
  does. **`a2dp-sink` takes audio from a telephone**, and it is what a speaker
  does. A device can do both, and `bluealsad` does neither unless you name it: the
  daemon starts with no profile and routes nothing.

  ## The plugin is userspace, and the kernel knows nothing about it

  No kernel audio driver is involved, so the plugin needs no module and no device
  node. What it does need is `alsa-lib` finding it, and Buildroot installs the
  configuration at `/etc/alsa/conf.d/20-bluealsa.conf` for that. A rootfs that
  drops `/etc/alsa/conf.d` gives `Unknown PCM bluealsa` and no sound.

  ## SBC is the codec, and that is a choice this package makes for you

  A2DP requires SBC and every device has it, so the default build carries SBC
  alone and nothing else. AAC, aptX and LDAC each need another library in the
  rootfs; Buildroot turns AAC on when `fdk-aac` is in the system, and neither this
  package nor NBPR provides one. A speaker that would have taken AAC takes SBC
  instead, which sounds slightly worse and always works.

  ## Dependencies

  `bluez5_utils` with its audio plugins, `libglib2`, `sbc`, and `alsa-lib` from
  the base system. Buildroot `select`s the audio plugins of BlueZ for you, and
  `NBPR.Bluez5Utils` builds them by default for the same reason.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "bluez-alsa",
    description: "Bluetooth Audio ALSA Backend.",
    homepage: "https://github.com/Arkq/bluez-alsa",
    daemons: [
      bluealsad: [
        path: "/usr/bin/bluealsad",
        opts: [
          profiles: [
            type: {:list, :string},
            required: true,
            flag: "-p",
            doc:
              "The profiles to route, such as `[\"a2dp-source\"]` to send audio to a speaker or `[\"a2dp-sink\"]` to take it from a telephone. A daemon with none routes nothing, which is why this is required rather than defaulted."
          ],
          device: [
            type: :string,
            flag: "-i",
            doc:
              "The HCI device to use, such as `hci0`. Unset takes whichever adapter BlueZ offers, which is the right answer on a board with one radio."
          ],
          syslog: [
            type: :boolean,
            default: false,
            flag: "--syslog",
            doc:
              "Send messages to syslog as well as to standard error. MuonTrap already carries standard error into the logger, so a Nerves device usually wants the default."
          ],
          loglevel: [
            type: :string,
            flag: "--loglevel",
            doc:
              "One of `error`, `warning`, `info` or `debug`. `debug` is what shows you why a speaker connected and then played nothing."
          ]
        ]
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
