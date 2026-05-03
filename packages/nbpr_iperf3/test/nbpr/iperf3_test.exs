defmodule NBPR.Iperf3Test do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Iperf3.__nbpr_package__()

    assert pkg.module == NBPR.Iperf3
    assert pkg.name == :iperf3
    assert pkg.version == 1
    assert pkg.br_package == "iperf3"
    assert pkg.description == "Iperf is a tool for active measurements of the maximum achievable bandwidth on IP networks."
    assert pkg.homepage == "http://software.es.net/iperf/index.html"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
