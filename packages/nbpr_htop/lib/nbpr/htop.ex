defmodule NBPR.Htop do
  @moduledoc """
  NBPR package for [`htop`](https://htop.dev/) — htop is an interactive text-mode process viewer for Linux. It aims to be a better top.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "htop",
    description: "Htop is an interactive text-mode process viewer for Linux.",
    homepage: "https://htop.dev/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
