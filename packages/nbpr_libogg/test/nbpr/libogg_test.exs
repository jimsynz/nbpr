defmodule NBPR.LiboggTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Libogg.__nbpr_package__()

    assert pkg.module == NBPR.Libogg
    assert pkg.name == :libogg
    assert pkg.version == 1
    assert pkg.br_package == "libogg"
    assert pkg.description == "Reference implementation of the Ogg container format"
    assert pkg.homepage == "https://xiph.org/ogg/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.build_opts == []
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
