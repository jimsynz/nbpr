defmodule NBPR.DockerEngine do
  @moduledoc """
  NBPR package for [`docker-engine`](https://github.com/moby/moby) — the
  Docker daemon (`dockerd`) and its helpers.

  Adds the upstream binaries to the rootfs at `/usr/bin/`:

    * `dockerd` — the Docker daemon
    * `docker-proxy` — userland port-forwarding helper `dockerd` spawns per
      published port

  and generates `NBPR.DockerEngine.Dockerd` — a MuonTrap-supervised GenServer
  the user adds to their own supervision tree:

      children = [
        {NBPR.Containerd.Containerd, root: "/data/containerd", state: "/run/containerd"},
        {NBPR.DockerEngine.Dockerd,
         containerd: "/run/containerd/containerd.sock",
         data_root: "/data/docker"}
      ]

  `dockerd` does **not** embed containerd — it drives the external
  `containerd` daemon over its socket. Start `NBPR.Containerd.Containerd`
  first (see `:nbpr_containerd`), then point `dockerd` at the same socket via
  the `:containerd` option.

  ## Companion packages

    * `:nbpr_containerd` / `:nbpr_runc` — the runtime `dockerd` delegates to
      (pulled in as deps).
    * `:nbpr_iptables` — `dockerd` shells out to `iptables` to set up the
      bridge network NAT and published-port rules (pulled in as a dep). If
      iptables isn't on `PATH`, start `dockerd` with `iptables: false` and
      manage networking yourself.
    * `:nbpr_docker_cli` — the `docker` client (separate package).

  ## Kernel and runtime requirements

  This package ships only binaries. `dockerd` cannot run containers unless
  the Nerves system kernel exposes the primitives the OCI runtime needs:
  cgroup v2 controllers, the PID/mount/network/user/IPC/UTS namespaces,
  overlayfs as a writable upper layer, and `veth`/`bridge`/netfilter
  (`nf_tables` or `ip_tables` + NAT/conntrack) for the default bridge
  network. Stock `nerves_system_*` kernels generally do **not** enable all of
  these — enabling them is a system-PR or system-fork task.

  `dockerd` also expects writable state. The defaults (`/var/lib/docker`,
  `/run/docker`) are not writable on a vanilla Nerves rootfs; redirect them
  onto a writable partition via the `:data_root` / `:exec_root` options (e.g.
  `/data/docker`).

  See `NBPR.DockerEngine.Dockerd` for the full option schema.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "docker-engine",
    description: "The Docker container engine daemon (dockerd)",
    homepage: "https://www.docker.com/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}],
    daemons: [
      dockerd: [
        path: "/usr/bin/dockerd",
        opts: [
          config_file: [
            type: :string,
            flag: "--config-file",
            doc: "Path to the daemon JSON config file (default `/etc/docker/daemon.json`)."
          ],
          containerd: [
            type: :string,
            flag: "--containerd",
            doc:
              "Path to the containerd gRPC socket `dockerd` should drive (e.g. `/run/containerd/containerd.sock`). Start `:nbpr_containerd` against the same socket."
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
            doc: "Socket/address to listen on (e.g. `unix:///run/docker.sock`)."
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
              "Let `dockerd` manage iptables rules for bridge networking (requires `:nbpr_iptables` on PATH). Pass `false` to manage networking yourself."
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
