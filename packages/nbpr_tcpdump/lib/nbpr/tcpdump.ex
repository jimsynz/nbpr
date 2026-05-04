defmodule NBPR.Tcpdump do
  @moduledoc """
  NBPR package for [`tcpdump`](https://www.tcpdump.org/) — a tool for network monitoring and data acquisition.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "tcpdump",
    description: "A tool for network monitoring and data acquisition.",
    homepage: "https://www.tcpdump.org/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
