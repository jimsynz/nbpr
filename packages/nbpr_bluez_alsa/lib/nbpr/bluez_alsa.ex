defmodule NBPR.BluezAlsa do
  @moduledoc """
  NBPR package for [`bluez-alsa`](https://github.com/Arkq/bluez-alsa) — Bluetooth
  audio as an ALSA device.

  **This is the piece that makes a Bluetooth speaker look like a sound card.** It
  installs a userspace ALSA plugin, so a program that already writes to ALSA needs
  no Bluetooth code at all: it opens `bluealsa:DEV=<address>` where it used to open
  `hw:0,0`, and `aplay` and every other ALSA program work unchanged.

  Adds `bluealsa` at `/usr/bin/bluealsa`, the ALSA plugins at
  `/usr/lib/alsa-lib/libasound_module_{pcm,ctl}_bluealsa.so`, and
  `bluealsa-cli`, `bluealsa-aplay` and `a2dpconf`. Generates
  `NBPR.BluezAlsa.Bluealsa` — a MuonTrap-supervised GenServer you add to your own
  supervision tree:

      children = [
        {NBPR.Dbus.DbusDaemon, config_file: "/etc/dbus-1/system.conf"},
        {NBPR.Bluez5Utils.Bluetoothd, []},
        {NBPR.BluezAlsa.Bluealsa, profiles: ["a2dp-source"]}
      ]

  The order is the order: the bus, then BlueZ, then this.

  ## The daemon is `bluealsa` here and `bluealsad` upstream

  **v5.0.0 renamed the daemon to `bluealsad` and the controller to
  `bluealsactl`, with no backward compatibility**, and this package wraps
  Buildroot's pin, which is v4.3.1 — the last release under the old names. So the
  names above are the v4 ones, and every v5-era answer you find elsewhere will
  use the other set. When Buildroot moves to v5 and Renovate bumps `@version`,
  the daemon declaration and this text move with it, and so does the generated
  module name.

  ## Which end of the link you are

  **`a2dp-source` sends audio to a speaker**, and it is what a stereo or a phone
  does. **`a2dp-sink` takes audio from a telephone**, and it is what a speaker
  does. A device can do both, and `bluealsa` does neither unless you name it: the
  daemon starts with no profile and routes nothing.

  ## The plugin is userspace, and the kernel knows nothing about it

  No kernel audio driver is involved, so the plugin needs no module and no device
  node. What it does need is `alsa-lib` finding two things.

  **The shared object.** `alsa-lib` looks for `libasound_module_pcm_bluealsa.so`
  in the plugin directory it was compiled with, which is `/usr/lib/alsa-lib` and
  is not where an NBPR package lands. This package therefore exports
  `ALSA_PLUGIN_DIR` into the BEAM environment at boot, and `alsa-lib` reads that
  variable in preference to the compiled-in path. Anything spawned from the BEAM
  — `aplay` through MuonTrap, a port, `System.cmd/2` — inherits it.

  **The PCM definition.** Buildroot installs it at
  `/etc/alsa/conf.d/20-bluealsa.conf`, and that path is in the rootfs of a
  Buildroot system and not in the priv dir of a package. Put the definition in
  your own `/etc/asound.conf` instead:

      pcm.bluealsa {
        type bluealsa
        device "AA:BB:CC:DD:EE:FF"
        profile "a2dp"
      }

  Without it, `aplay -D bluealsa` gives `Unknown PCM bluealsa` and no sound.

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
    runtime_env: [{"ALSA_PLUGIN_DIR", "${NBPR_PRIV}/usr/lib/alsa-lib"}],
    daemons: [
      bluealsa: [
        path: "/usr/bin/bluealsa",
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
