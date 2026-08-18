defmodule NBPR.FftwSingleTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.FftwSingle.__nbpr_package__()

      assert pkg.module == NBPR.FftwSingle
      assert pkg.name == :fftw_single
      assert pkg.version == 1
      assert pkg.br_package == "fftw-single"

      assert pkg.description ==
               "Library for computing Fast Fourier Transforms, single precision"

      assert pkg.homepage == "http://www.fftw.org"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end
  end

  describe "build options" do
    test "fast maps to its Buildroot flag and defaults off" do
      pkg = NBPR.FftwSingle.__nbpr_package__()

      assert Keyword.keys(pkg.build_opts) == [:fast]
      assert pkg.build_opt_extensions[:fast].br_flag == "BR2_PACKAGE_FFTW_FAST"

      validated = NimbleOptions.validate!([], NimbleOptions.new!(pkg.build_opts))
      assert validated[:fast] == false
    end
  end
end
