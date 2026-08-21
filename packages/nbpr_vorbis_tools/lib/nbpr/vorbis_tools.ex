defmodule NBPR.VorbisTools do
  @moduledoc """
  NBPR package for [`vorbis-tools`](https://xiph.org/vorbis/) — Xiph's
  command-line Ogg Vorbis utilities.

  Six binaries land in this package's priv dir, which `NBPR.Application`
  prepends to `PATH` at boot, so `System.cmd/2` finds them by name:

    * `oggenc` — encode WAV/AIFF/raw to Ogg Vorbis
    * `oggdec` — decode Ogg Vorbis to WAV or raw
    * `ogg123` — play or transcode a stream, locally or over HTTP
    * `ogginfo` — report bitrate, channels, comments, stream integrity
    * `vorbiscomment` — read and write Vorbis comment tags
    * `vcut` — split a stream at a sample position, without re-encoding

  For example:

      {_output, 0} = System.cmd("oggenc", ["-q", "6", "-o", "/data/clip.ogg", "/data/clip.wav"])

  ## Dependencies

  Buildroot's vorbis-tools `select`s libao, libogg, libvorbis and libcurl
  unconditionally, and no Nerves system ships any of them. Since an nbpr
  artefact carries only its own Buildroot files-list, each arrives as its own
  package — hence the four `:nbpr_lib*` dependencies. libcurl is there for
  `ogg123`'s HTTP streaming, and comes with the same caveat as anything else
  doing TLS on a stock Nerves system: no CA bundle in the rootfs.

  ## ogg123 cannot reach a speaker yet

  `ogg123` outputs through libao, and libao's output plugins are found by
  `opendir` on a path fixed at build time (`/usr/lib/ao/plugins-4`) — a path
  nbpr's priv-dir install doesn't populate. The ALSA plugin is therefore
  invisible at runtime and only libao's built-in file drivers work:

      # writes a file — fine
      System.cmd("ogg123", ["-d", "wav", "-f", "/data/out.wav", "/data/clip.ogg"])

      # wants a speaker — no driver, fails
      System.cmd("ogg123", ["/data/clip.ogg"])

  See `NBPR.Libao` for the detail and what a fix needs. Every other binary
  here is unaffected: none of them touches libao.

  ## FLAC input

  The `flac` option adds `libFLAC` to the build, letting `oggenc` take
  `.flac` input directly and `ogg123` play FLAC. It's off by default,
  matching Buildroot, and turning it on means adding the library to your own
  dependencies too — otherwise `mix nbpr.fetch`'s shared-library check will
  tell you `libFLAC.so.14` is missing from the firmware:

      # config/target.exs
      config :nbpr_vorbis_tools, build_opts: [flac: true]

      # mix.exs
      {:nbpr_flac, "~> 1.0", organization: "nbpr"}

  Buildroot's vorbis-tools also picks up Speex and Opus input when those
  packages are enabled. Neither is exposed here: nothing packages
  `libspeex` or `libopusfile` for NBPR yet, so the option would only produce
  an artefact with sonames nothing in the firmware can resolve.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "vorbis-tools",
    description: "Command-line player, encoder and decoder for Ogg Vorbis",
    homepage: "https://xiph.org/vorbis/",
    build_opts: [
      flac: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_FLAC",
        doc:
          "Build with libFLAC, so `oggenc` accepts `.flac` input and `ogg123` plays it. Off by default, as in Buildroot. Enabling it requires `:nbpr_flac` in your own dependencies — the artefact links `libFLAC.so.14` and nothing else in the firmware provides it."
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
