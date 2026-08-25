defmodule NBPR.Libvips do
  @moduledoc """
  NBPR package for [`libvips`](https://www.libvips.org/) — the demand-driven
  image processing library, and its command-line tools.

  Ships `libvips.so.42` and `libvips-cpp.so.42` on `LD_LIBRARY_PATH`, with
  headers and pkg-config in the staging slice for a NIF that wants to link the
  library rather than shell out. Alongside them go all four of upstream's
  tools, in this package's priv dir, which `NBPR.Application` prepends to
  `PATH` at boot:

    * `vips` — the multicall driver. Every libvips operation is a subcommand:
      `vips resize`, `vips thumbnail`, `vips composite`, and so on. `vips
      --list classes` enumerates them on the device.
    * `vipsthumbnail` — the one worth reaching for first. It picks a
      shrink-on-load factor before decoding, so the full-size image never
      exists.
    * `vipsheader` — dimensions, bands, interpretation and loader, without
      decoding pixels.
    * `vipsedit` — rewrite the header of a `.vips` file in place.

  ```elixir
  {_, 0} = System.cmd("vipsthumbnail", ["/data/cover.jpg", "--size", "300x300",
                                        "-o", "/data/thumb.jpg"])
  {info, 0} = System.cmd("vipsheader", ["/data/cover.jpg"])
  ```

  The tools aren't optional — upstream's meson build installs them
  unconditionally and Buildroot doesn't intervene, so the library and the CLI
  are one artefact.

  ## Why this rather than ImageMagick

  libvips evaluates a pipeline in horizontal strips, demand-driven, with a
  thread per strip. A resize holds a few scanlines of working buffer, not the
  image — so peak memory scales with image *width* and thread count, not
  width x height. `NBPR.Imagemagick`, by contrast, is a Q16 HDRI build whose
  pixel cache is 16 bytes per RGBA pixel: 144 MB for a 3000x3000 image, twice
  that mid-resize.

  What you pay for it is rootfs space. libvips is built on GObject, so it
  drags in `:nbpr_libglib2` — much the largest thing in this dependency chain
  — plus `:nbpr_expat`, `:nbpr_libffi` and `:nbpr_pcre2`. For a firmware that
  does one thumbnail a day, ImageMagick is the smaller answer. For anything
  doing sustained image work on a 512 MB board, this is the one that fits.

  ## Formats

  JPEG and PNG arrive through the two options below, and cover the common
  case. Beyond them:

    * **GIF reads, and does not write.** libvips vendors `libnsgif`, so
      `gifload` is compiled in and needs no dependency — animation included.
      Writing needs `cgif`, which upstream Buildroot doesn't package at all,
      so there is no option to turn it on.
    * **Built-in and always present:** PPM/PGM/PBM/PFM, Radiance HDR, Analyze,
      raw, CSV, matrix, and libvips' own `.vips` format.
    * **Absent:** TIFF, WebP, HEIF/AVIF, JPEG-XL, JPEG-2000, SVG, PDF,
      OpenEXR, colour management via lcms2, EXIF metadata, and text rendering
      through pango. Buildroot wires all of these to `BR2_PACKAGE_*` symbols,
      so they're a `build_opt` away — but for the reason `NBPR.VorbisTools`
      gives for Speex and Opus: nothing packages those libraries for NBPR yet,
      so the option would only produce an artefact linking sonames nothing in
      the firmware can resolve. Package the library first, then the option.

  Buildroot hard-disables OpenEXR, OpenSlide, cfitsio and pangocairo whatever
  the configuration.

  ImageMagick is a special case among those absent delegates. `:nbpr_imagemagick`
  *is* packaged, and setting `BR2_PACKAGE_IMAGEMAGICK` would get Buildroot to
  configure `-Dmagick=enabled` — but libvips builds that delegate as a
  `dlopen`ed module under a libdir fixed at compile time, which is the
  `NBPR.Libao` failure mode, and the formats it would add are ones libvips
  already reads natively. It isn't offered.

  ## Memory and threads

  Three environment variables are worth setting on a target. None is in this
  package's `runtime_env`, because that mechanism colon-joins when a variable
  is already set — right for a search path, wrong for every one of these.

    * **`VIPS_CONCURRENCY`** caps worker threads per pipeline. Left unset,
      libvips uses one per hardware thread, so a 4-core Pi runs four strips at
      once and holds four working buffers. On a board also running the BEAM,
      `1` or `2` is usually the better trade. `--vips-concurrency` does the
      same per invocation.

    * **`TMPDIR`** decides where libvips spills. On Nerves `/tmp` is a tmpfs,
      so the default consumes the RAM you were trying to protect. Point it at
      `/data`.

    * **`VIPS_DISC_THRESHOLD`** (default 100 MB) is the size above which an
      image opened for random access goes to a temp file in `TMPDIR` instead
      of memory. Sequential pipelines — which is what `vipsthumbnail` and most
      `vips` subcommands build — never hit it. Operations that need random
      access, like `rot45` or a large `composite`, do.

  ## No SIMD acceleration

  libvips can use libhwy for vectorised resize and convolution, and orc for
  runtime-generated vector code. Neither is available here.

  orc is packaged by Buildroot and wired into `libvips.mk`, but nothing
  packages it for NBPR. libhwy is a harder no: Buildroot has a `highway`
  package, but `libvips.mk` never adds it to `LIBVIPS_DEPENDENCIES`, and under
  `BR2_PER_PACKAGE_DIRECTORIES` a package that isn't a declared dependency
  isn't in the sysroot — so setting the symbol would achieve nothing. Fixing
  that means a patch upstream in Buildroot, not a `build_opt` here.

  libvips falls back to GCC's vector extensions, which it detects and uses for
  the hot arithmetic paths. Slower than libhwy, far from scalar.

  ## Loadable modules

  Buildroot configures `-Dmodules=enabled`, and libvips scans
  `<libdir>/vips-modules-8.18` at init. Only five delegates can be built as
  modules — HEIF, JPEG-XL, ImageMagick, OpenSlide and poppler — and none of
  them is enabled here, so nothing is built and the scan finds an empty path.

  That's why there's no `VIPSHOME` in `runtime_env`. libvips derives its
  module directory from a prefix fixed at compile time, which nbpr's priv-dir
  install doesn't match, and `VIPSHOME` is the documented override. It would
  be needed the moment any of those five is turned on — but adding it now
  would be configuration for a case that can't arise.

  ## JPEG provider

  The `jpeg` option sets two symbols, not one, for the reason
  `NBPR.Imagemagick` sets out at length: `BR2_PACKAGE_JPEG` is a virtual
  package whose provider `choice` defaults to turbo only where SIMD is
  available, which is false on ARMv6. Naming `BR2_PACKAGE_JPEG_TURBO` as well
  pins one provider — and so one soname — across every target in the matrix.
  See `NBPR.JpegTurbo`.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "libvips",
    description: "Demand-driven image processing library and command-line tools",
    homepage: "https://www.libvips.org/",
    build_opts: [
      fftw: [
        type: :boolean,
        default: false,
        br_flag: ["BR2_PACKAGE_FFTW", "BR2_PACKAGE_FFTW_DOUBLE"],
        doc:
          "Build with double-precision FFTW, enabling the frequency-domain operations — `fwfft`, `invfft`, `freqmult` and the mask builders. Off by default: it's a niche corner of libvips and build options are part of the artefact cache key, so turning it on means a source build. Enabling it requires `:nbpr_fftw_double` in your own dependencies — the artefact links `libfftw3.so.3` and nothing else in the firmware provides it. Sets the parent `BR2_PACKAGE_FFTW` as well as the precision, because the precision symbols are declared inside `if BR2_PACKAGE_FFTW` and kconfig drops an ungated one."
      ],
      jpeg: [
        type: :boolean,
        default: true,
        br_flag: ["BR2_PACKAGE_JPEG", "BR2_PACKAGE_JPEG_TURBO"],
        doc:
          "Build with libjpeg-turbo, so libvips reads and writes JPEG and `vipsthumbnail` can shrink on load. On by default; turning it off configures libvips with `-Djpeg=disabled` and means a source build. Sets both the virtual `BR2_PACKAGE_JPEG` and the `BR2_PACKAGE_JPEG_TURBO` provider, because kconfig's default provider differs by target."
      ],
      png: [
        type: :boolean,
        default: true,
        br_flag: "BR2_PACKAGE_LIBPNG",
        doc:
          "Build with libpng, so libvips reads and writes PNG. On by default; turning it off configures libvips with `-Dpng=disabled` and means a source build."
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
