defmodule NBPR.LibaoTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Libao.__nbpr_package__()

    assert pkg.module == NBPR.Libao
    assert pkg.name == :libao
    assert pkg.version == 1
    assert pkg.br_package == "libao"
    assert pkg.description == "Cross-platform audio output library"
    assert pkg.homepage == "https://www.xiph.org/ao/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.build_opts == []
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
