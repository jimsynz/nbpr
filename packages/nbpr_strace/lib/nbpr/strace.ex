defmodule NBPR.Strace do
  @moduledoc """
  NBPR package for [`strace`](https://strace.io) — a useful diagnostic, instructional, and debugging tool. Allows you to track what system calls a program makes while it is running.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "strace",
    description: "A useful diagnostic, instructional, and debugging tool.",
    homepage: "https://strace.io",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
