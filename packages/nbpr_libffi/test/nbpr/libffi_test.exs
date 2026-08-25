defmodule NBPR.LibffiTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Libffi.__nbpr_package__()

    assert pkg.module == NBPR.Libffi
    assert pkg.name == :libffi
    assert pkg.version == 1
    assert pkg.br_package == "libffi"
    assert pkg.description == "Portable foreign-function interface library"
    assert pkg.homepage == "https://sourceware.org/libffi/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
