defmodule NBPR.LibpcapTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Libpcap.__nbpr_package__()

    assert pkg.module == NBPR.Libpcap
    assert pkg.name == :libpcap
    assert pkg.version == 1
    assert pkg.br_package == "libpcap"
    assert pkg.description == "A system-independent library for user-level network packet capture."
    assert pkg.homepage == "https://www.tcpdump.org/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
