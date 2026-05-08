# nbpr_cni_plugins

> Reference Container Network Interface plugins.

[`cni-plugins`](https://github.com/containernetworking/plugins) packaged for Nerves. Tracks the upstream Buildroot `cni-plugins` package — this release wraps **1.7.1**.

Installs every reference plugin under `/opt/cni/bin/`: IPAM (`dhcp`,
`host-local`, `static`), main (`bridge`, `dummy`, `host-device`,
`ipvlan`, `loopback`, `macvlan`, `ptp`, `tap`, `vlan`) and meta
(`bandwidth`, `firewall`, `portmap`, `sbr`, `tuning`, `vrf`).

Licence: Apache-2.0.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_cni_plugins, "~> 1.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.

## Important: kernel and runtime caveats

This package ships **only the plugin binaries**. Each plugin has its own
kernel-feature requirements; stock `nerves_system_*` kernels generally
do **not** enable everything needed. Before expecting a given plugin to
work, ensure your chosen Nerves system enables, at minimum:

  * `bridge`, `portmap`, `firewall` — `CONFIG_BRIDGE`, `CONFIG_VETH`,
    `CONFIG_NETFILTER`, `nf_nat`, `nf_conntrack`, `iptables` (or
    `nf_tables`), and the `xt_*` matches your CNI config relies on
  * `macvlan`, `ipvlan`, `vlan` — `CONFIG_MACVLAN`, `CONFIG_IPVLAN`,
    `CONFIG_VLAN_8021Q`
  * `tap` — `CONFIG_TUN`
  * `bandwidth` — traffic-control / `CONFIG_NET_SCH_*` and the relevant
    classifier
  * `sbr`, `vrf` — policy routing, `CONFIG_NET_VRF`, multiple routing
    tables
  * `dhcp` — userland helper; needs the rest of the host network stack
    in working order

These knobs are part of the **kernel config of the system you build
against** (`nerves_system_<board>`). NBPR is explicitly out of scope for
kernel changes; if your target system doesn't enable them, you will need
to fork the system or open a PR upstream to enable them.

Plugin selection happens through CNI configuration files (typically in
`/etc/cni/net.d/`), which this package **does not** install — that's a
deployment-specific concern.

## Supervision

CNI plugins are short-lived binaries invoked by the runtime
(`containerd`/`runc`/`nerdctl`/etc.) when a container is created or
destroyed. There is no daemon to supervise, so this package generates no
supervisor child spec.

