defmodule NBPR.Imagemagick do
  @moduledoc """
  NBPR package for [`ImageMagick`](https://imagemagick.org/) — the image
  conversion and manipulation suite.

  Ships the `magick` binary into this package's priv dir, which
  `NBPR.Application` prepends to `PATH` at boot, so `System.cmd/2` finds it by
  name. ImageMagick 7 is a single multicall binary — the ImageMagick 6 names
  (`convert`, `identify`, `mogrify`, `montage`, …) are subcommands of it:

      {_output, 0} = System.cmd("magick", ["/data/cover.jpg", "-resize", "300x300", "/data/thumb.png"])
      {info, 0} = System.cmd("magick", ["identify", "/data/cover.jpg"])

  Alongside it go `libMagickCore`, `libMagickWand` and `libMagick++` on
  `LD_LIBRARY_PATH`, with headers and pkg-config files in the staging slice
  for a NIF that wants to link the library rather than shell out.

  The `magick` binary is built because Buildroot passes `--with-utilities`
  when `BR2_INSTALL_LIBSTDCPP` is set, which every Nerves system does. It
  isn't an option here — it follows the system.

  ## Formats

  JPEG and PNG arrive through the two options below. **GIF needs neither an
  option nor a dependency**: ImageMagick implements GIF and LZW itself, so
  `coders/gif.c` compiles into `libMagickCore` and links nothing beyond it.
  Read and write both work out of the box, animation included. Buildroot's
  `giflib` package is irrelevant to this one.

  The same goes for ImageMagick's other self-contained coders — BMP, PNM/PPM,
  TGA, XPM, MIFF, and the rest of the built-in set.

  Buildroot builds ImageMagick with a long list of delegates hard-disabled
  regardless of configuration: OpenCL, OpenMP, djvu, dps, flif, fpx, gslib,
  gvc, jbig, **jxl**, lqr, **openexr**, **openjp2**, perl, **raqm**, wmf and
  X11. So no JPEG-2000, no JPEG-XL, no OpenEXR, no PDF or PostScript, and no
  complex-script text shaping. This is not desktop ImageMagick.

  Buildroot exposes fourteen more delegates behind `BR2_PACKAGE_*` symbols —
  TIFF, WebP, freetype, fontconfig, lcms2, pango, librsvg, libheif, libraw
  and friends. None are offered here, for the reason `NBPR.VorbisTools` gives
  for Speex and Opus: nothing packages those libraries for NBPR yet, so the
  option would only produce an artefact linking sonames nothing in the
  firmware can resolve.

  ## Memory: this is a Q16 HDRI build

  Buildroot passes neither `--with-quantum-depth` nor `--disable-hdri`, so
  ImageMagick's upstream defaults stand: a 16-bit quantum with HDRI, which
  makes `Quantum` a 32-bit float. The soname says so — `libMagickCore-7.Q16HDRI.so`.

  Four bytes per channel is a lot on a target. A 3000x3000 RGBA image is
  3000 x 3000 x 4 x 4 = **144 MB** of pixel cache, and a resize generally
  wants two buffers. On a 512 MB board also running the BEAM, that is fatal.
  The same image at 1400x1400 is 31 MB, which is unremarkable — so whether
  this matters is entirely a question of your input sizes.

  Neither flag is a Buildroot kconfig symbol, and `imagemagick/Config.in`
  declares no options at all, so this cannot be configured through a
  `build_opt`. Changing it means vendoring the Buildroot package.

  Three things help meanwhile:

    * **`-define jpeg:size=WxH`** hands the target size to libjpeg, which
      DCT-scales during decode — the full-size image never materialises. This
      is the big one, and it costs nothing:

          System.cmd("magick", ["-define", "jpeg:size=300x300", "/data/cover.jpg",
                                "-resize", "300x300", "/data/thumb.jpg"])

      JPEG only. PNG and GIF still decode in full, which is exactly why the
      quantum depth still matters.

    * **Resource limits.** Past its memory limit ImageMagick spills the pixel
      cache to disk rather than dying, so oversized inputs degrade to slow
      instead of fatal. `-limit` sets this per invocation:

          System.cmd("magick", ["-limit", "memory", "64MiB",
                                "-limit", "map", "64MiB",
                                "/data/cover.png", "-resize", "300x300", "/data/thumb.png"])

      Spilling writes to flash, so treat it as a safety net rather than a
      steady state — and point it somewhere durable. ImageMagick's default
      temporary path is `/tmp`, which on Nerves is a tmpfs, so spilling there
      would consume the very RAM the limit exists to protect. Set
      `MAGICK_TEMPORARY_PATH=/data` in your own environment to move it.

      These aren't set in this package's `runtime_env` on purpose. That
      mechanism colon-joins when several packages (or your own environment)
      set the same variable, which is right for a search path and wrong for a
      scalar — a user-set `MAGICK_MEMORY_LIMIT` would end up as
      `64MiB:256MiB` and fail to parse. Only `MAGICK_CONFIGURE_PATH`, which
      genuinely is a colon-separated search path, is set below.

    * **`MAGICK_WIDTH_LIMIT` / `MAGICK_HEIGHT_LIMIT`** reject absurd inputs
      outright, if you would rather fail fast than swap.

  ## Configuration files

  ImageMagick compiles in absolute paths for its XML configuration —
  `/etc/ImageMagick-7` and `/usr/share/ImageMagick-7` — which don't exist
  under nbpr's priv-dir install. `MAGICK_CONFIGURE_PATH` in the `runtime_env`
  below points at the staged copy.

  For JPEG, PNG and GIF work this is belt-and-braces: ImageMagick has
  compiled-in defaults for the magic and colour tables, and the files that
  would otherwise be missing (`type.xml`, `delegates.xml`) govern fonts and
  external delegates, neither of which this build has.

  Coders are *not* affected — Buildroot doesn't pass `--with-modules`, so
  every coder is linked into `libMagickCore` and none is `dlopen`ed at
  runtime.

  ## JPEG provider

  The `jpeg` option sets two symbols, not one. `BR2_PACKAGE_JPEG` is a
  Buildroot virtual package with a `choice` of providers beneath it, and the
  choice defaults to turbo only where SIMD is available — which is false on
  ARMv6, so `rpi0` would otherwise build IJG `libjpeg` release 10 while the
  firmware ships `:nbpr_jpeg_turbo`'s `-DWITH_JPEG8=ON` build. Different
  sonames, unresolvable at runtime. Naming both symbols pins turbo on every
  target. See `NBPR.JpegTurbo`.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "imagemagick",
    description: "Image conversion and manipulation suite",
    homepage: "https://imagemagick.org/",
    build_opts: [
      jpeg: [
        type: :boolean,
        default: true,
        br_flag: ["BR2_PACKAGE_JPEG", "BR2_PACKAGE_JPEG_TURBO"],
        doc:
          "Build with libjpeg-turbo, so `magick` reads and writes JPEG. On by default; turning it off configures Buildroot's imagemagick with `--without-jpeg` and means a source build. Sets both the virtual `BR2_PACKAGE_JPEG` and the `BR2_PACKAGE_JPEG_TURBO` provider, because kconfig's default provider differs by target."
      ],
      png: [
        type: :boolean,
        default: true,
        br_flag: "BR2_PACKAGE_LIBPNG",
        doc:
          "Build with libpng, so `magick` reads and writes PNG. On by default; turning it off configures Buildroot's imagemagick with `--without-png` and means a source build."
      ]
    ],
    runtime_env: [{"MAGICK_CONFIGURE_PATH", "${NBPR_PRIV}/etc/ImageMagick-7"}],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
