defmodule NBPR.BalenaEngine do
  @moduledoc """
  NBPR package for [`balena-engine`](https://github.com/balena-os/balena-engine)
  — balenaEngine, a Moby-derived container engine purpose-built for embedded
  and IoT use cases and compatible with Docker containers.

  Unlike the decomposed Docker stack (`:nbpr_docker_engine` +
  `:nbpr_containerd` + `:nbpr_runc` + `:nbpr_docker_cli`), balenaEngine ships
  as a **single static binary** that bundles the daemon, containerd, the
  OCI runtime, the proxy and the client. The package installs it at
  `/usr/bin/balena-engine` with the upstream multi-call symlinks alongside:

    * `balena-engine-daemon` — the engine daemon (the `dockerd` analogue)
    * `balena-engine-containerd` / `-containerd-shim` / `-containerd-ctr`
    * `balena-engine-runc` — the bundled OCI runtime
    * `balena-engine-proxy` — userland published-port forwarder

  `balena-engine` is also the CLI, so there is no separate client package:
  invoke it from user code via `System.cmd/2`:

      {out, 0} =
        System.cmd("balena-engine", ["ps"],
          env: [{"DOCKER_HOST", "unix:///run/balena-engine.sock"}])

  It generates `NBPR.BalenaEngine.BalenaEngine` — a MuonTrap-supervised
  GenServer the user adds to their own supervision tree:

      children = [
        {NBPR.BalenaEngine.BalenaEngine,
         data_root: "/data/balena-engine",
         host: "unix:///run/balena-engine.sock"}
      ]

  Because containerd and runc are baked in, there is nothing else to start
  first — this is the "batteries-included" choice for constrained targets,
  where the decomposed Docker stack is the alternative for users who want to
  manage those components independently. Pick one or the other, not both.

  ## Companion packages

    * `:nbpr_iptables` — balenaEngine shells out to `iptables` to set up the
      bridge network NAT and published-port rules (pulled in as a dep). If
      iptables isn't on `PATH`, start the daemon with `iptables: false` and
      manage networking yourself.

  ## Kernel and runtime requirements

  This package ships only binaries. The daemon cannot run containers unless
  the Nerves system kernel exposes the primitives the OCI runtime needs:
  cgroup controllers, the PID/mount/network/user/IPC/UTS namespaces,
  overlayfs as a writable upper layer, and `veth`/`bridge`/netfilter
  (`nf_tables` or `ip_tables` + NAT/conntrack) for the default bridge
  network. Stock `nerves_system_*` kernels generally do **not** enable all of
  these — enabling them is a system-PR or system-fork task.

  The daemon also expects writable state. The defaults (`/var/lib/docker`,
  `/run`) are not writable on a vanilla Nerves rootfs; redirect them onto a
  writable partition via the `:data_root` / `:exec_root` options (e.g.
  `/data/balena-engine`).

  See `NBPR.BalenaEngine.BalenaEngine` for the full option schema.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "balena-engine",
    description: "Moby-derived container engine for embedded and IoT, Docker-compatible",
    homepage: "https://github.com/balena-os/balena-engine",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}],
    daemons: [
      balena_engine: [
        path: "/usr/bin/balena-engine-daemon",
        opts: [
          config_file: [
            type: :string,
            flag: "--config-file",
            doc: "Path to the daemon JSON config file (default `/etc/docker/daemon.json`)."
          ],
          data_root: [
            type: :string,
            flag: "--data-root",
            doc:
              "Root directory for persistent state (images, volumes; default `/var/lib/docker` is not writable on a vanilla Nerves rootfs)."
          ],
          exec_root: [
            type: :string,
            flag: "--exec-root",
            doc: "Root directory for runtime state (default `/var/run/docker`)."
          ],
          host: [
            type: :string,
            flag: "--host",
            doc: "Socket/address to listen on (e.g. `unix:///run/balena-engine.sock`)."
          ],
          pidfile: [
            type: :string,
            flag: "--pidfile",
            doc: "Path to the daemon PID file (default `/var/run/docker.pid`)."
          ],
          storage_driver: [
            type: :string,
            flag: "--storage-driver",
            doc: "Storage driver to use (`overlay2` is the sensible default on Nerves)."
          ],
          iptables: [
            type: :boolean,
            flag: "--iptables",
            doc:
              "Let the daemon manage iptables rules for bridge networking (requires `:nbpr_iptables` on PATH). Pass `false` to manage networking yourself."
          ],
          log_level: [
            type: :string,
            flag: "--log-level",
            doc: "Log level: `debug`, `info`, `warn`, `error`, `fatal`."
          ]
        ]
      ]
    ]
end
