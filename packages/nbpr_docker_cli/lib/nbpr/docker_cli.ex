defmodule NBPR.DockerCli do
  @moduledoc """
  NBPR package for [`docker-cli`](https://github.com/docker/cli) — the
  `docker` command-line client.

  Adds the `docker` binary to the rootfs at `/usr/bin/docker`. It's a client
  only: it talks to a running `dockerd` (see `:nbpr_docker_engine`) over the
  daemon socket, so start the engine first. Invoke from user code via
  `System.cmd/2`:

      {out, 0} = System.cmd("docker", ["ps"], env: [{"DOCKER_HOST", "unix:///run/docker.sock"}])

  `docker compose` and `docker buildx` are separate CLI plugins — see
  `:nbpr_docker_compose` and `:nbpr_docker_cli_buildx`.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "docker-cli",
    description: "The Docker command-line client",
    homepage: "https://github.com/docker/cli",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
