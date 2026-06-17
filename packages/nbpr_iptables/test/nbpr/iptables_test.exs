defmodule NBPR.IptablesTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Iptables.__nbpr_package__()

    assert pkg.module == NBPR.Iptables
    assert pkg.name == :iptables
    assert pkg.version == 1
    assert pkg.br_package == "iptables"
    assert pkg.description == "Linux kernel firewall, NAT, and packet mangling tools."
    assert pkg.homepage == "http://www.netfilter.org/projects/iptables/index.html"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
