defmodule NBPR.DockerCliBuildxTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.DockerCliBuildx.__nbpr_package__()

    assert pkg.module == NBPR.DockerCliBuildx
    assert pkg.name == :docker_cli_buildx
    assert pkg.version == 1
    assert pkg.br_package == "docker-cli-buildx"
    assert pkg.description == "Buildx is a Docker CLI plugin for extended build capabilities with BuildKit."
    assert pkg.homepage == "https://github.com/docker/buildx"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
