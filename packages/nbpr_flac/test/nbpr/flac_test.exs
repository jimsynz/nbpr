defmodule NBPR.FlacTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Flac.__nbpr_package__()

      assert pkg.module == NBPR.Flac
      assert pkg.name == :flac
      assert pkg.version == 1
      assert pkg.br_package == "flac"
      assert pkg.description == "Free Lossless Audio Codec libraries and command-line tools"
      assert pkg.homepage == "https://xiph.org/flac/"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end
  end

  describe "build options" do
    test "ogg enables Buildroot's libogg and defaults on" do
      pkg = NBPR.Flac.__nbpr_package__()

      assert Keyword.keys(pkg.build_opts) == [:ogg]
      assert pkg.build_opt_extensions[:ogg].br_flag == "BR2_PACKAGE_LIBOGG"

      validated = NimbleOptions.validate!([], NimbleOptions.new!(pkg.build_opts))
      assert validated[:ogg] == true
    end
  end
end
