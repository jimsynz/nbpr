defmodule NBPR.TcpdumpTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Tcpdump.__nbpr_package__()

    assert pkg.module == NBPR.Tcpdump
    assert pkg.name == :tcpdump
    assert pkg.version == 1
    assert pkg.br_package == "tcpdump"
    assert pkg.description == "A tool for network monitoring and data acquisition."
    assert pkg.homepage == "https://www.tcpdump.org/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
