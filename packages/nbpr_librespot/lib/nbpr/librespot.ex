defmodule NBPR.Librespot do
  @moduledoc """
  NBPR package for [`librespot`](https://github.com/librespot-org/librespot) — a
  device that a Spotify application can cast to.

  Adds `librespot` to the rootfs at `/usr/bin/librespot`. Generates
  `NBPR.Librespot.Librespot` — a MuonTrap-supervised GenServer you add to your own
  supervision tree:

      children = [
        {NBPR.Librespot.Librespot, name: "Kitchen", device: "hw:0,0"}
      ]

  librespot never detaches, so there is no foreground flag to remember.

  ## Read this before you ship it

  **A Spotify Premium account is required**, and the librespot project says of
  itself: *"Using this code to connect to Spotify's API is probably forbidden by
  them. Use at your own risk."* That sentence is the whole of the decision, and it
  belongs to whoever ships the product rather than to this package. The licensed
  alternative is Spotify's Embedded SDK, which needs a company agreement and
  per-device certification, and is not something a package can provide.

  ## This one is vendored

  librespot is not in Buildroot mainline, so this package carries its own
  Buildroot external tree under `priv/buildroot` and declares `br_external_path:`
  rather than `br_package:`. NBPR adds that tree to `BR2_EXTERNAL` for the build,
  and everything else works the way a mainline package does.

  **The build is a Rust cross-compile**, through Buildroot's `cargo-package`
  infrastructure and `host-rustc`. It takes considerably longer than a C package,
  and it needs a target architecture that `host-rustc` supports, which the
  `Config.in` of the vendored tree says.

  ## Three features, and each one had to be named

  The default set is `native-tls`, `rodio-backend` and `with-libmdns`, and rodio
  drags in every audio backend the platform has. `--no-default-features` keeps
  those out of the tree and takes the other two defaults with it, so the vendored
  `.mk` names all three again.

  - **`alsa-backend`** is the audio, and the only backend a Nerves rootfs can
    serve.
  - **`rustls-tls-webpki-roots`** is the TLS. librespot refuses to compile without
    one — the check is in `librespot-oauth`, because that crate comes first — and
    this one is pure Rust, so the build links no OpenSSL of the system and the
    roots are compiled in rather than read out of the rootfs. An appliance that
    carries no CA bundle therefore still reaches Spotify, and the roots move with a
    firmware upgrade.
  - **`with-libmdns`** is what lets a telephone find the device. The alternatives
    need Avahi or `dns-sd`, and a Nerves rootfs has neither.

  **The list goes in twice.** `pkg-cargo.mk` gives `cargo build` the
  `_CARGO_BUILD_OPTS` and then gives `cargo install` the `_CARGO_INSTALL_OPTS`, and
  an install that names no features builds the default set all over again. Setting
  only the first got the build through and then stopped the install with `Could not
  find directory of OpenSSL installation`.

  ## It listens, and a device that no person asked for should not

  librespot advertises itself with zeroconf and listens for a controller, which is
  how a telephone finds it with no account on the device. That is a port, and an
  appliance that opens one a person did not ask for is an appliance with a door in
  it. Start the daemon from a setting rather than from the top of your supervision
  tree.

  ## Where the credentials go

  `cache` names a directory that librespot writes the credentials and the audio
  cache into. On a Nerves device that has to be the writable partition, and
  `disable_audio_cache: true` is worth considering beside it: the audio cache
  writes every track a person plays to the card, and an SD card has a finite
  number of writes in it.
  """

  use NBPR.BrPackage,
    version: 1,
    br_external_path: "buildroot",
    description: "An open source client library for Spotify",
    homepage: "https://github.com/librespot-org/librespot",
    daemons: [
      librespot: [
        path: "/usr/bin/librespot",
        opts: [
          name: [
            type: :string,
            required: true,
            flag: "--name",
            doc:
              "The name that a Spotify application shows for this device. Required, because the default is the word `Librespot` and a household with two of them cannot tell one from the other."
          ],
          backend: [
            type: :string,
            default: "alsa",
            flag: "--backend",
            doc:
              "The audio backend. `alsa` is the only one that this build carries: see the moduledoc."
          ],
          device: [
            type: :string,
            flag: "--device",
            doc:
              "The ALSA device to play to, such as `hw:0,0` or a `bluealsa:DEV=…` of `NBPR.BluezAlsa`. Unset takes the default device, which is rarely what a board with a USB DAC wants."
          ],
          device_type: [
            type: :string,
            default: "speaker",
            flag: "--device-type",
            doc:
              "The icon that a Spotify application draws for this device. `speaker`, `avr`, `stb`, `computer` and several more."
          ],
          bitrate: [
            type: :integer,
            flag: "--bitrate",
            doc: "96, 160 or 320 kbps. Unset leaves librespot at its default of 160."
          ],
          cache: [
            type: :string,
            flag: "--cache",
            doc:
              "The directory for the credentials and the audio cache. On a Nerves device this must be on the writable partition, and a device that names none asks a person to sign in again at every boot."
          ],
          disable_audio_cache: [
            type: :boolean,
            default: false,
            flag: "--disable-audio-cache",
            doc:
              "Keep the credentials and not the audio. Worth thinking about on a board that runs for years on an SD card: the audio cache writes every track that a person plays."
          ],
          initial_volume: [
            type: :integer,
            flag: "--initial-volume",
            doc:
              "The volume, 0 to 100, that this device starts at. A stereo that came back from a power cut at full volume is one that a person remembers."
          ],
          volume_ctrl: [
            type: :string,
            flag: "--volume-ctrl",
            doc:
              "`cubic`, `fixed`, `linear` or `log`. `fixed` hands the volume to whatever is downstream, which is what a device with a volume control of its own wants."
          ],
          mixer: [
            type: :string,
            flag: "--mixer",
            doc: "`softvol` or `alsa`. `alsa` sets the level on the card rather than in software."
          ],
          zeroconf_port: [
            type: :integer,
            flag: "--zeroconf-port",
            doc:
              "The port that the discovery listener binds. Unset takes an ephemeral one, which is fine for a home network and awkward for a firewall rule."
          ],
          disable_discovery: [
            type: :boolean,
            default: false,
            flag: "--disable-discovery",
            doc:
              "Open no discovery listener. A device set this way needs credentials, and it is the only way to run librespot without listening for anything."
          ],
          onevent: [
            type: :string,
            flag: "--onevent",
            doc:
              "A program to run when the player changes what it is doing. This is how a firmware learns that Spotify took the sound card, which nothing else tells it."
          ],
          quiet: [
            type: :boolean,
            default: false,
            flag: "--quiet",
            doc: "Log less."
          ],
          verbose: [
            type: :boolean,
            default: false,
            flag: "--verbose",
            doc:
              "Log more. The first thing to reach for when a telephone will not find the device."
          ]
        ]
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
