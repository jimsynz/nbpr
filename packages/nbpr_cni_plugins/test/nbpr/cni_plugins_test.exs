defmodule NBPR.CniPluginsTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.CniPlugins.__nbpr_package__()

    assert pkg.module == NBPR.CniPlugins
    assert pkg.name == :cni_plugins
    assert pkg.version == 1
    assert pkg.br_package == "cni-plugins"
    assert pkg.description == "Reference Container Network Interface plugins"
    assert pkg.homepage == "https://github.com/containernetworking/plugins"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
