defmodule NBPR.DockerComposeTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.DockerCompose.__nbpr_package__()

    assert pkg.module == NBPR.DockerCompose
    assert pkg.name == :docker_compose
    assert pkg.version == 1
    assert pkg.br_package == "docker-compose"
    assert pkg.description == "Multi-container applications with the Docker CLI."
    assert pkg.homepage == "https://github.com/docker/compose"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
