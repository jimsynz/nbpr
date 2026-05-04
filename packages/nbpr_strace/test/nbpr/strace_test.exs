defmodule NBPR.StraceTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Strace.__nbpr_package__()

    assert pkg.module == NBPR.Strace
    assert pkg.name == :strace
    assert pkg.version == 1
    assert pkg.br_package == "strace"
    assert pkg.description == "A useful diagnostic, instructional, and debugging tool."
    assert pkg.homepage == "https://strace.io"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
