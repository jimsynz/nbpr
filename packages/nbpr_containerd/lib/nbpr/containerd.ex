defmodule NBPR.Containerd do
  @moduledoc """
  NBPR package for [`containerd`](https://containerd.io/) — an OCI-compliant
  container runtime daemon.

  Adds the upstream containerd binaries to the rootfs at `/usr/bin/`:

    * `containerd` — the main daemon
    * `containerd-shim-runc-v2` — the shim that containerd spawns per
      container; must be present alongside `containerd`
    * `ctr` — debug CLI

  and generates `NBPR.Containerd.Containerd` — a MuonTrap-supervised
  GenServer the user adds to their own supervision tree:

      children = [
        {NBPR.Containerd.Containerd, config: "/etc/containerd/config.toml"}
      ]

  Most of containerd's behaviour is set in its TOML config file rather than
  through CLI flags, so the daemon's runtime options are deliberately
  minimal.

  ## Kernel and runtime requirements

  This package ships only the binary. Containerd cannot start a container
  unless the underlying Nerves system kernel exposes the namespace and
  cgroup primitives the OCI runtime needs (cgroup v1/v2 controllers, PID,
  mount, network, user, IPC and UTS namespaces, overlayfs as a writable
  upper layer, veth/bridge/netfilter for networking, seccomp). Stock
  `nerves_system_*` kernels generally do **not** enable all of these — see
  the package README for the full caveat.

  Containerd also expects writable state directories. The defaults
  (`/var/lib/containerd`, `/run/containerd`) are not writable on a vanilla
  Nerves rootfs; either redirect them via the config file (e.g. into
  `/data/containerd/`) or override `--root` and `--state` via the daemon
  opts.

  See `NBPR.Containerd.Containerd` for the full option schema.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "containerd",
    description: "OCI-compliant container runtime daemon",
    homepage: "https://containerd.io/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}],
    daemons: [
      containerd: [
        path: "/usr/bin/containerd",
        opts: [
          config: [
            type: :string,
            flag: "--config",
            doc: "Path to the containerd TOML config file."
          ],
          root: [
            type: :string,
            flag: "--root",
            doc:
              "Root directory for persistent data (overrides `[root]` in the config; default `/var/lib/containerd` is not writable on a vanilla Nerves rootfs)."
          ],
          state: [
            type: :string,
            flag: "--state",
            doc:
              "State directory for runtime data (overrides `[state]` in the config; default `/run/containerd` is on tmpfs)."
          ],
          address: [
            type: :string,
            flag: "--address",
            doc: "Path to the gRPC socket (default `/run/containerd/containerd.sock`)."
          ],
          log_level: [
            type: :string,
            flag: "--log-level",
            doc: "Log level: `debug`, `info`, `warn`, `error`, `fatal`, `panic`."
          ]
        ]
      ]
    ]
end
