defmodule NBPR.ExpatTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Expat.__nbpr_package__()

    assert pkg.module == NBPR.Expat
    assert pkg.name == :expat
    assert pkg.version == 1
    assert pkg.br_package == "expat"
    assert pkg.description == "Stream-oriented XML parser library"
    assert pkg.homepage == "https://libexpat.github.io/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
