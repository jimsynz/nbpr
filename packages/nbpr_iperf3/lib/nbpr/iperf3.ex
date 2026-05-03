defmodule NBPR.Iperf3 do
  @moduledoc """
  NBPR package for [`iperf3`](http://software.es.net/iperf/index.html) — iperf is a tool for active measurements of the maximum achievable bandwidth on IP networks. It supports tuning of various parameters related to timing, protocols, and buffers. For each test it reports the bandwidth, loss, and other parameters. It's a redesign of the NLANR/DAST iperf(2) and is not backward compatible.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "iperf3",
    description: "Iperf is a tool for active measurements of the maximum achievable bandwidth on IP networks.",
    homepage: "http://software.es.net/iperf/index.html",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
