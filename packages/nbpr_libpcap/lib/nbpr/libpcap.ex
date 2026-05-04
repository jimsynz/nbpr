defmodule NBPR.Libpcap do
  @moduledoc """
  NBPR package for [`libpcap`](https://www.tcpdump.org/) — a system-independent library for user-level network packet capture.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "libpcap",
    description: "A system-independent library for user-level network packet capture.",
    homepage: "https://www.tcpdump.org/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
