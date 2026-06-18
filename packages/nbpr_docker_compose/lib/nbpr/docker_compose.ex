defmodule NBPR.DockerCompose do
  @moduledoc """
  NBPR package for [`docker-compose`](https://github.com/docker/compose) — the
  Compose v2 plugin for defining and running multi-container applications.

  Ships the `docker-compose` binary (the `docker compose` CLI plugin). It
  drives a running Docker daemon, so it depends on `:nbpr_docker_cli` and
  needs `:nbpr_docker_engine` running. Point it at the daemon socket the same
  way as the `docker` client.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "docker-compose",
    description: "Multi-container applications with the Docker CLI.",
    homepage: "https://github.com/docker/compose",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
