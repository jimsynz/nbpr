defmodule NBPR.JpegTurbo do
  @moduledoc """
  NBPR package for [`libjpeg-turbo`](https://libjpeg-turbo.org/) — the
  SIMD-accelerated JPEG codec, and Buildroot's default provider of the
  `libjpeg` API.

  Ships `libjpeg.so.62` and `libturbojpeg.so.0` under this package's priv
  dir; `NBPR.Application` prepends it to `LD_LIBRARY_PATH` at boot so sibling
  packages resolve the sonames. The staging slice carries the headers, the
  `.so` symlinks and the pkg-config files, so a NIF can cross-compile against
  either the classic `libjpeg` API or the simpler TurboJPEG one.

  Packaged because no Nerves system ships a JPEG library, while anything
  decoding JPEG needs one.

  ## Why this package and not `libjpeg`

  Buildroot models JPEG as a virtual package: `BR2_PACKAGE_JPEG` turns it on,
  and a `choice` picks the provider — plain `libjpeg` or `jpeg-turbo`.

  The choice defaults to turbo only `if BR2_PACKAGE_JPEG_SIMD_SUPPORT`, which
  is off on ARMv6 — `rpi0` is an `arm1176jzf_s` with no NEON. Left to the
  default, that one target would build IJG `libjpeg` instead, and the two
  providers are *not* interchangeable here: Buildroot's `libjpeg` is IJG
  release 10, while `jpeg-turbo` is configured `-DWITH_JPEG8=ON`. Different
  sonames, so a consumer built against one won't resolve against the other.

  So this package names `jpeg-turbo` explicitly, and consumers that enable
  JPEG must set `BR2_PACKAGE_JPEG_TURBO` alongside `BR2_PACKAGE_JPEG` rather
  than leaving the provider to kconfig — see `NBPR.Imagemagick`'s `jpeg`
  option for the shape. Turbo builds fine on ARMv6, it just doesn't use SIMD
  there. One provider, one soname, everywhere.

  Selecting it needs both `BR2_PACKAGE_JPEG=y` and `BR2_PACKAGE_JPEG_TURBO=y`
  — the symbol is declared inside the `choice` in `package/jpeg/Config.in`,
  not in `package/jpeg-turbo/`, which holds only a `.mk` and a
  `Config.in.options`. `NBPR.Buildroot.Defconfig` derives that gate from the
  tree; without it `make olddefconfig` drops the symbol and the build produces
  no output at all.

  ## Licensing

  Three licences in one package: the classic libjpeg API is under the IJG
  licence, the TurboJPEG wrapper is BSD-3-Clause, and the SIMD routines are
  Zlib. Which bind depends on which of the two APIs you link.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "jpeg-turbo",
    description: "SIMD-accelerated JPEG codec providing the libjpeg API",
    homepage: "https://libjpeg-turbo.org/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
