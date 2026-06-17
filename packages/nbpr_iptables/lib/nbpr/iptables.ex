defmodule NBPR.Iptables do
  @moduledoc """
  NBPR package for [`iptables`](https://www.netfilter.org/projects/iptables/) —
  the userspace tools for the Linux kernel firewall (NAT, filtering, mangling).

  Adds the `iptables`/`ip6tables` binaries (and their `libxtables` shared
  libraries) to the rootfs under `/usr/sbin/`. Primarily here so
  `:nbpr_docker_engine` can set up bridge-network NAT and published-port
  rules; it's equally usable standalone via `System.cmd/2`.

  The binaries require the kernel's netfilter machinery (`ip_tables`/`nf_*`
  with NAT and conntrack) to be enabled in the active Nerves system — shipping
  the userspace tools doesn't enable the kernel side.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "iptables",
    description: "Linux kernel firewall, NAT, and packet mangling tools.",
    homepage: "http://www.netfilter.org/projects/iptables/index.html",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
