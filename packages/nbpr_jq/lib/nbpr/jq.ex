defmodule NBPR.Jq do
  @moduledoc """
  NBPR package for [`jq`](https://jqlang.github.io/jq/) — a lightweight,
  flexible command-line JSON processor.

  Adds the `jq` binary to the firmware rootfs at `/usr/bin/jq`. Invoke from
  user code via `System.cmd/2`:

      {output, 0} = System.cmd("jq", [".name", "/srv/erlang/config.json"])

  See `NBPR.BrPackage` and the workspace `PLAN.md` for the broader contract.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "jq",
    description: "Lightweight JSON processor",
    homepage: "https://jqlang.github.io/jq/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz"}]
end
