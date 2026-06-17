defmodule NBPR.DockerCliTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.DockerCli.__nbpr_package__()

    assert pkg.module == NBPR.DockerCli
    assert pkg.name == :docker_cli
    assert pkg.version == 1
    assert pkg.br_package == "docker-cli"
    assert pkg.description == "The Docker command-line client"
    assert pkg.homepage == "https://github.com/docker/cli"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
