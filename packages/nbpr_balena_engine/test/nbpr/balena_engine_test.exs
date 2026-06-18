defmodule NBPR.BalenaEngineTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.BalenaEngine.__nbpr_package__()

    assert pkg.module == NBPR.BalenaEngine
    assert pkg.name == :balena_engine
    assert pkg.version == 1
    assert pkg.br_package == "balena-engine"

    assert pkg.description ==
             "Moby-derived container engine for embedded and IoT, Docker-compatible"

    assert pkg.homepage == "https://github.com/balena-os/balena-engine"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert [balena_engine] = pkg.daemons
    assert balena_engine.name == :balena_engine
    assert balena_engine.path == "/usr/bin/balena-engine-daemon"
    assert pkg.kernel_modules == []
  end
end
