defmodule NBPR.LibvipsTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Libvips.__nbpr_package__()

      assert pkg.module == NBPR.Libvips
      assert pkg.name == :libvips
      assert pkg.version == 1
      assert pkg.br_package == "libvips"
      assert pkg.description == "Demand-driven image processing library and command-line tools"
      assert pkg.homepage == "https://www.libvips.org/"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end
  end

  describe "build options" do
    test "jpeg and png default on, fftw off" do
      pkg = NBPR.Libvips.__nbpr_package__()

      assert Keyword.keys(pkg.build_opts) == [:fftw, :jpeg, :png]

      validated = NimbleOptions.validate!([], NimbleOptions.new!(pkg.build_opts))
      assert validated[:fftw] == false
      assert validated[:jpeg] == true
      assert validated[:png] == true
    end

    # `BR2_PACKAGE_JPEG` is a virtual package whose provider `choice` defaults
    # to turbo only where SIMD is available. On ARMv6 (rpi0) that picks IJG
    # libjpeg 10, whose soname doesn't match the `-DWITH_JPEG8=ON` build
    # `:nbpr_jpeg_turbo` ships — so the provider is pinned, not inferred.
    test "jpeg pins the provider as well as the virtual package" do
      pkg = NBPR.Libvips.__nbpr_package__()

      assert pkg.build_opt_extensions[:jpeg].br_flag ==
               ["BR2_PACKAGE_JPEG", "BR2_PACKAGE_JPEG_TURBO"]
    end

    test "png enables Buildroot's libpng" do
      pkg = NBPR.Libvips.__nbpr_package__()

      assert pkg.build_opt_extensions[:png].br_flag == "BR2_PACKAGE_LIBPNG"
    end

    # Buildroot's libvips wires the frequency-domain operations to the
    # double-precision FFTW alone; `BR2_PACKAGE_FFTW_SINGLE` does nothing here.
    # The parent symbol comes too: the precision symbols are declared inside
    # `if BR2_PACKAGE_FFTW`, so `make olddefconfig` drops an ungated one and
    # the package silently never builds.
    test "fftw selects the double-precision build under its parent symbol" do
      pkg = NBPR.Libvips.__nbpr_package__()

      assert pkg.build_opt_extensions[:fftw].br_flag ==
               ["BR2_PACKAGE_FFTW", "BR2_PACKAGE_FFTW_DOUBLE"]
    end

    # GIF load is compiled in via the vendored libnsgif, and GIF save needs
    # cgif, which upstream Buildroot doesn't package — so there's nothing for
    # an option to switch either way.
    test "there is no gif option" do
      pkg = NBPR.Libvips.__nbpr_package__()

      refute Keyword.has_key?(pkg.build_opts, :gif)
    end
  end

  # libvips derives its module directory from a compile-time prefix, which
  # nbpr's priv-dir install doesn't match. Nothing here builds a module — the
  # five that can be are all disabled — so VIPSHOME would be configuration for
  # a case that can't arise.
  test "declares no runtime env" do
    assert NBPR.Libvips.__nbpr_package__().runtime_env == []
  end
end
