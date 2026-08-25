defmodule NBPR.ImagemagickTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Imagemagick.__nbpr_package__()

      assert pkg.module == NBPR.Imagemagick
      assert pkg.name == :imagemagick
      assert pkg.version == 1
      assert pkg.br_package == "imagemagick"
      assert pkg.description == "Image conversion and manipulation suite"
      assert pkg.homepage == "https://imagemagick.org/"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end
  end

  describe "build options" do
    test "jpeg and png default on" do
      pkg = NBPR.Imagemagick.__nbpr_package__()

      assert Keyword.keys(pkg.build_opts) == [:jpeg, :png]

      validated = NimbleOptions.validate!([], NimbleOptions.new!(pkg.build_opts))
      assert validated[:jpeg] == true
      assert validated[:png] == true
    end

    # `BR2_PACKAGE_JPEG` is a virtual package whose provider `choice` defaults
    # to turbo only where SIMD is available. On ARMv6 (rpi0) that picks IJG
    # libjpeg 10, whose soname doesn't match the `-DWITH_JPEG8=ON` build
    # `:nbpr_jpeg_turbo` ships — so the provider is pinned, not inferred.
    test "jpeg pins the provider as well as the virtual package" do
      pkg = NBPR.Imagemagick.__nbpr_package__()

      assert pkg.build_opt_extensions[:jpeg].br_flag ==
               ["BR2_PACKAGE_JPEG", "BR2_PACKAGE_JPEG_TURBO"]
    end

    test "png enables Buildroot's libpng" do
      pkg = NBPR.Imagemagick.__nbpr_package__()

      assert pkg.build_opt_extensions[:png].br_flag == "BR2_PACKAGE_LIBPNG"
    end

    # GIF is implemented inside libMagickCore and links nothing beyond it, so
    # there's deliberately no option and no dependency for it.
    test "there is no gif option" do
      pkg = NBPR.Imagemagick.__nbpr_package__()

      refute Keyword.has_key?(pkg.build_opts, :gif)
    end
  end

  describe "runtime env" do
    # ImageMagick compiles in absolute paths for its XML config, which don't
    # exist under nbpr's priv-dir install.
    test "redirects the configure path into the package's priv dir" do
      env = NBPR.Imagemagick.__nbpr_package__().runtime_env

      assert {"MAGICK_CONFIGURE_PATH", "${NBPR_PRIV}/etc/ImageMagick-7"} in env
    end

    # `runtime_env` colon-joins when a variable is already set, which is right
    # for a search path and wrong for a scalar: a user-set MAGICK_MEMORY_LIMIT
    # would become "64MiB:256MiB" and fail to parse. Only path-like variables
    # belong here; the limits are documented for the caller to set instead.
    test "carries only path-like variables" do
      env = NBPR.Imagemagick.__nbpr_package__().runtime_env

      assert Keyword.keys(Enum.map(env, fn {k, v} -> {String.to_atom(k), v} end)) ==
               [:MAGICK_CONFIGURE_PATH]
    end
  end
end
