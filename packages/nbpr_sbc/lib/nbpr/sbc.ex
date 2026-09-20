defmodule NBPR.Sbc do
  @moduledoc """
  NBPR package for [`sbc`](http://www.bluez.org/) — the codec that every Bluetooth
  audio device speaks.

  Adds `libsbc.so` to the rootfs. There is no daemon and no tool in the default
  build: this is a library that `NBPR.BluezAlsa` links against, and it is here
  because that package needs it and nothing in a Nerves system provides it.

  **A2DP requires SBC, so every speaker and every pair of headphones has it.**
  AAC, aptX and LDAC are the optional ones, and a link that cannot agree on any of
  those falls back here. That makes this the one codec worth carrying: it sounds
  slightly worse than the rest and it always works.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "sbc",
    description:
      "An audio codec to connect bluetooth high quality audio devices like headphones or loudspeakers.",
    homepage: "http://www.bluez.org/",
    build_opts: [
      tools: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_SBC_TOOLS",
        doc:
          "Build the command-line encoder and decoder. They pull in `libsndfile`, which is not an NBPR package, so leaving this off is the only build that resolves today."
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
