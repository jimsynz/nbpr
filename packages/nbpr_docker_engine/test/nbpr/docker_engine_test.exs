defmodule NBPR.DockerEngineTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.DockerEngine.__nbpr_package__()

    assert pkg.module == NBPR.DockerEngine
    assert pkg.name == :docker_engine
    assert pkg.version == 1
    assert pkg.br_package == "docker-engine"
    assert pkg.description == "The Docker container engine daemon (dockerd)"
    assert pkg.homepage == "https://www.docker.com/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert [dockerd] = pkg.daemons
    assert dockerd.name == :dockerd
    assert dockerd.path == "/usr/bin/dockerd"
    assert pkg.kernel_modules == []
  end
end
