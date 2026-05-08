defmodule NBPR.Runc do
  @moduledoc """
  NBPR package for [`runc`](https://github.com/opencontainers/runc) — the
  reference OCI runtime for spawning and running containers.

  `runc` is a CLI invoked by higher-level runtimes such as
  [`containerd`](https://hexdocs.pm/nbpr_containerd) — this package ships
  the binary at `/usr/sbin/runc` but does not generate any supervisor
  child spec. There is no long-running daemon to wire into a supervision
  tree.

  ## Kernel and runtime requirements

  This package ships only the binary. It does not enable the kernel
  features `runc` needs to start a container — namespaces, cgroups,
  overlayfs, seccomp, and (often) capabilities/AppArmor/SELinux. Stock
  `nerves_system_*` kernels generally do not enable all of these. See the
  package README for the full caveat.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "runc",
    description: "Reference OCI container runtime CLI",
    homepage: "https://github.com/opencontainers/runc",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
