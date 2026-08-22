defmodule NBPR.Flac do
  @moduledoc """
  NBPR package for [`flac`](https://xiph.org/flac/) — the Free Lossless
  Audio Codec: its libraries plus the `flac` and `metaflac` command-line
  tools.

  Ships `flac` (encode/decode) and `metaflac` (edit tags and STREAMINFO
  without re-encoding) into this package's priv dir, which
  `NBPR.Application` prepends to `PATH` at boot, so `System.cmd/2` finds
  them by name:

      {_output, 0} = System.cmd("flac", ["--best", "-o", "/data/out.flac", "/data/in.wav"])

  Alongside them go `libFLAC.so.14` and, because Nerves toolchains ship a
  C++ compiler, `libFLAC++.so.11` — both on `LD_LIBRARY_PATH`, with headers
  and pkg-config files in the staging slice for a NIF that wants to link the
  codec directly rather than shell out.

  ## Ogg support

  The `ogg` option is on by default, which is why this package depends on
  `:nbpr_libogg`: without it Buildroot configures `--disable-ogg` and
  `libFLAC` loses the Ogg-FLAC container — `.oga` files, and `flac --ogg`.
  Native FLAC (`.flac`) is unaffected either way. Turning it off drops the
  `libogg.so.0` link, at the cost of a source build:

      config :nbpr_flac, build_opts: [ogg: false]

  `:nbpr_libogg` stays in this package's dependencies regardless — a Hex
  dependency can't be conditional on a build option — so an `ogg: false`
  firmware carries libogg unused. Drop it from your own deps if that
  matters; nothing else will resolve `libogg.so.0` for you if a sibling
  package needs it.

  ## Licensing

  Three licences in one Buildroot package, and which one binds depends on
  what you ship: `libFLAC` and `libFLAC++` are BSD-3-Clause, the `flac` and
  `metaflac` binaries are GPL-2.0-or-later, and the remaining support
  libraries are LGPL-2.1-or-later. Linking the libraries from a NIF is not
  the same proposition as shipping the tools.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "flac",
    description: "Free Lossless Audio Codec libraries and command-line tools",
    homepage: "https://xiph.org/flac/",
    build_opts: [
      ogg: [
        type: :boolean,
        default: true,
        br_flag: "BR2_PACKAGE_LIBOGG",
        doc:
          "Build `libFLAC` with Ogg-FLAC support, so `.oga` files and `flac --ogg` work. On by default; turning it off configures Buildroot's flac with `--disable-ogg` and drops the `libogg.so.0` link."
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
