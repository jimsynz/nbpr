defmodule NBPR.VorbisToolsTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.VorbisTools.__nbpr_package__()

      assert pkg.module == NBPR.VorbisTools
      assert pkg.name == :vorbis_tools
      assert pkg.version == 1
      assert pkg.br_package == "vorbis-tools"
      assert pkg.description == "Command-line player, encoder and decoder for Ogg Vorbis"
      assert pkg.homepage == "https://xiph.org/vorbis/"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end

    test "declares musl unsupported" do
      pkg = NBPR.VorbisTools.__nbpr_package__()

      assert pkg.unsupported_libc == [:musl]
    end
  end

  describe "build options" do
    test "flac maps to its Buildroot flag and defaults off" do
      pkg = NBPR.VorbisTools.__nbpr_package__()

      assert Keyword.keys(pkg.build_opts) == [:flac]
      assert pkg.build_opt_extensions[:flac].br_flag == "BR2_PACKAGE_FLAC"

      validated = NimbleOptions.validate!([], NimbleOptions.new!(pkg.build_opts))
      assert validated[:flac] == false
    end
  end
end
