defmodule NBPR.LibpngTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Libpng.__nbpr_package__()

    assert pkg.module == NBPR.Libpng
    assert pkg.name == :libpng
    assert pkg.version == 1
    assert pkg.br_package == "libpng"
    assert pkg.description == "Library for reading and writing PNG images"
    assert pkg.homepage == "http://www.libpng.org/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
