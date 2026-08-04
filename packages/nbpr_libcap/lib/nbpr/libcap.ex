defmodule NBPR.Libcap do
  @moduledoc """
  NBPR package for [`libcap`](https://sites.google.com/site/fullycapable/) —
  the userspace interface to POSIX 1003.1e capabilities, which split root's
  all-or-nothing privilege into individually grantable pieces.

  Ships `libcap.so.2` and `libpsx.so.2` under this package's priv dir;
  `NBPR.Application` prepends it to `LD_LIBRARY_PATH` at boot so sibling
  packages resolve the sonames.

  No stock Nerves system carries libcap, so any package linking it needs this
  one in the firmware too — an nbpr artefact only carries its own Buildroot
  files-list, not its dependencies'. `:nbpr_chrony` is the current case:
  Buildroot's chrony `select`s libcap unconditionally, so `chronyd` always
  links `libcap.so.2`.

  ## Capabilities on Nerves

  The BEAM runs as root on a Nerves target, so nothing here is needed to
  *grant* privilege — it's already total. libcap matters because daemons
  written to drop privilege link against it regardless of whether they end up
  dropping anything.

  The `tools` option is off by default for the same reason. `setcap` also
  wants filesystem xattr and security-label support in the kernel, and a
  writable filesystem to set attributes on — neither of which describes a
  Nerves squashfs rootfs.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "libcap",
    description: "Userspace interface to POSIX 1003.1e capabilities",
    homepage: "https://sites.google.com/site/fullycapable/",
    build_opts: [
      tools: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_LIBCAP_TOOLS",
        doc:
          "Install the `setcap`, `getcap`, `getpcaps` and `capsh` utilities alongside the libraries. Off by default — they need kernel xattr/security-label support and a writable filesystem to be much use, and the BEAM already runs as root on a Nerves target."
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
