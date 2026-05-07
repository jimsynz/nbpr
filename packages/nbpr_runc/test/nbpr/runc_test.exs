defmodule NBPR.RuncTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Runc.__nbpr_package__()

    assert pkg.module == NBPR.Runc
    assert pkg.name == :runc
    assert pkg.version == 1
    assert pkg.br_package == "runc"
    assert pkg.description == "Reference OCI container runtime CLI"
    assert pkg.homepage == "https://github.com/opencontainers/runc"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
