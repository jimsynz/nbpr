defmodule NBPR.CniPlugins do
  @moduledoc """
  NBPR package for the [reference CNI
  plugins](https://github.com/containernetworking/plugins) — the standard
  set of network plugins that container runtimes (e.g.
  [`containerd`](https://hexdocs.pm/nbpr_containerd)) invoke through the
  Container Network Interface spec to attach containers to networks.

  Installs every reference plugin under `/opt/cni/bin/` (the conventional
  CNI binary directory). The full set as of the bundled upstream release:

    * **IPAM:** `dhcp`, `host-local`, `static`
    * **Main:** `bridge`, `dummy`, `host-device`, `ipvlan`, `loopback`,
      `macvlan`, `ptp`, `tap`, `vlan`
    * **Meta:** `bandwidth`, `firewall`, `portmap`, `sbr`, `tuning`, `vrf`

  No daemon, no application module — these are short-lived binaries
  invoked on demand by the runtime.

  ## Kernel and runtime requirements

  This package ships only the plugin binaries. They will not function
  unless the underlying kernel exposes the networking primitives each
  plugin uses (veth, bridge, netfilter/iptables for `bridge`/`portmap`,
  TUN/TAP for `tap`, VLAN/macvlan/ipvlan link types for those plugins,
  traffic control / `cls_*` for `bandwidth`, etc.). Stock
  `nerves_system_*` kernels generally do not enable all of these — see
  the package README for the full caveat.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "cni-plugins",
    description: "Reference Container Network Interface plugins",
    homepage: "https://github.com/containernetworking/plugins",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
