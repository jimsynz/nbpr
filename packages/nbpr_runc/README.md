# nbpr_runc

> Reference OCI container runtime CLI.

[`runc`](https://github.com/opencontainers/runc) packaged for Nerves. Tracks the upstream Buildroot `runc` package — this release wraps **1.3.0**.

Licences: Apache-2.0 (runc), LGPL-2.1-only (libseccomp linked in).


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_runc, "~> 1.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Source: <https://github.com/jimsynz/nbpr>.

## Important: kernel and runtime caveats

This package ships **only the `runc` binary** at `/usr/bin/runc`. It
does not patch the kernel, alter the rootfs, or pull in supporting
userspace plumbing. Stock `nerves_system_*` kernels generally do **not**
enable everything `runc` needs. Before expecting `runc` to start a
container, ensure your chosen Nerves system enables, at minimum:

  * cgroups v1 *and/or* v2 with the `cpu`, `cpuset`, `memory`, `pids`,
    `devices` and `freezer` controllers
  * the full namespace family: `CONFIG_PID_NS`, `CONFIG_NET_NS`,
    `CONFIG_USER_NS`, `CONFIG_UTS_NS`, `CONFIG_IPC_NS`, mount namespaces
  * `CONFIG_OVERLAY_FS` available as a writable upper layer
  * `CONFIG_SECCOMP` (strongly recommended; runc was built with libseccomp
    linked in)
  * Kernel capability support and (optionally) AppArmor/SELinux LSM hooks
    if you intend to use them

These knobs are part of the **kernel config of the system you build
against** (`nerves_system_<board>`). NBPR is explicitly out of scope for
kernel changes; if your target system doesn't enable them, you will need
to fork the system or open a PR upstream to enable them.

## Supervision

`runc` is a CLI tool, not a daemon. There is no generated supervisor
child spec — invoke `runc` directly (typically through a higher-level
runtime such as [`containerd`](https://hexdocs.pm/nbpr_containerd)).

