defmodule NBPR.FftwDouble do
  @moduledoc """
  NBPR package for [`fftw`](http://www.fftw.org) in double precision — the
  library for computing Fast Fourier Transforms, built with `double` as the
  floating-point type.

  Ships `libfftw3.so.3` under this package's priv dir; `NBPR.Application`
  prepends it to `LD_LIBRARY_PATH` at boot so consumers resolve the soname.
  The staging slice carries the headers and the `.so` symlink, so a NIF can
  cross-compile against it.

  ## Precision is per-package

  Buildroot builds each fftw precision as a separate package from one
  tarball, each producing its own library with its own soname. NBPR follows
  that split, so precision is chosen by which package you depend on:

    * `:nbpr_fftw_double` — `libfftw3.so.3`, symbols `fftw_*` (this one)
    * `:nbpr_fftw_single` — `libfftw3f.so.3`, symbols `fftwf_*`

  They don't conflict, and code linking both `-lfftw3` and `-lfftw3f` — as
  Eigen's FFT bindings do — needs both packages in the firmware.

  Buildroot also has long-double and quad-precision variants. Neither is
  packaged here yet; quad is x86-only in any case, since kconfig hides it
  without gcc's `__float128`.

  ## Accuracy versus speed

  The `fast` option builds with `-O3 -ffast-math`, which lets the compiler
  reorder floating-point arithmetic. It's off by default, matching
  Buildroot: FFT results are what most callers came for, and the
  transformations aren't ones you want applied without asking.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "fftw-double",
    description: "Library for computing Fast Fourier Transforms, double precision",
    homepage: "http://www.fftw.org",
    build_opts: [
      fast: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_FFTW_FAST",
        doc:
          "Build with `-O3 -ffast-math`, trading accuracy for speed. Off by default, as in Buildroot — say yes only if you need the speed and can live with inaccurate results."
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
