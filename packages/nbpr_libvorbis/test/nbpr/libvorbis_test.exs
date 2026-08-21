defmodule NBPR.LibvorbisTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Libvorbis.__nbpr_package__()

    assert pkg.module == NBPR.Libvorbis
    assert pkg.name == :libvorbis
    assert pkg.version == 1
    assert pkg.br_package == "libvorbis"
    assert pkg.description == "Reference encoder and decoder for the Ogg Vorbis audio codec"
    assert pkg.homepage == "https://xiph.org/vorbis/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.build_opts == []
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
