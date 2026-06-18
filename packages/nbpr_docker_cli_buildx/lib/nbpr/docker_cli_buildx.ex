defmodule NBPR.DockerCliBuildx do
  @moduledoc """
  NBPR package for [`docker-cli-buildx`](https://github.com/docker/buildx) —
  the `docker buildx` CLI plugin for BuildKit-backed image builds.

  Ships the `docker-buildx` plugin binary. It extends the `docker` client
  (depends on `:nbpr_docker_cli`) and drives a running Docker daemon
  (`:nbpr_docker_engine`) to build images.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "docker-cli-buildx",
    description: "Buildx is a Docker CLI plugin for extended build capabilities with BuildKit.",
    homepage: "https://github.com/docker/buildx",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
