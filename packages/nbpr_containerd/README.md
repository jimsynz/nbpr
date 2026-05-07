# nbpr_containerd

> Containerd is a daemon to control runC.

[`containerd`](https://containerd.io/) packaged for Nerves. Tracks the upstream Buildroot `containerd` package — this release wraps **2.0.7**.

Licence: Apache-2.0.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_containerd, "~> 2.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.

## Important: kernel and runtime caveats

This package ships **only the `containerd` binary**. It does not patch
the kernel, alter the rootfs layout, or pull in supporting userspace
plumbing. In particular, **stock `nerves_system_*` kernels do not enable
the features containerd needs to actually run a container**. Before
expecting `containerd` to be useful you must, at minimum, ensure your
chosen Nerves system enables:

  * cgroups v1 *and/or* v2 with the `cpu`, `cpuset`, `memory`, `pids`,
    `devices` and `freezer` controllers
  * the full namespace family: `CONFIG_PID_NS`, `CONFIG_NET_NS`,
    `CONFIG_USER_NS`, `CONFIG_UTS_NS`, `CONFIG_IPC_NS`, mount namespaces
  * `CONFIG_OVERLAY_FS` available as a writable upper layer (Nerves uses
    overlayfs for the A/B partition, but the snapshotter wants its own
    writable upper)
  * `CONFIG_VETH`, `CONFIG_BRIDGE`, `CONFIG_NETFILTER`, the `nf_nat`,
    `nf_conntrack` and `iptables` matches, plus
    `CONFIG_NETFILTER_XT_MATCH_*` selectors that your CNI configuration
    relies on
  * `CONFIG_SECCOMP` (strongly recommended)

These knobs are part of the **kernel config of the system you build
against** (`nerves_system_<board>`). NBPR is explicitly out of scope for
kernel changes; if your target system doesn't enable them, you will need
to fork the system or open a PR upstream to enable them.

You will also want a working OCI runtime (`runc` — see
[`nbpr_runc`](../nbpr_runc/)) and a CNI plugin set (see
[`nbpr_cni_plugins`](../nbpr_cni_plugins/)) for any non-trivial use.

### State directories

Containerd's defaults (`/var/lib/containerd`, `/run/containerd`) are not
writable on a vanilla Nerves rootfs. Override them via the TOML config
or the `root:`/`state:` daemon options to point at writable storage,
typically under `/data/`.

## Supervision

`NBPR.Containerd.Containerd` is a MuonTrap-supervised wrapper. Add it to
your application's supervision tree:

    children = [
      {NBPR.Containerd.Containerd, config: "/etc/containerd/config.toml"}
    ]

See the module's `@moduledoc` for the full option schema.

