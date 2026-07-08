defmodule NBPR.Kmod do
  @moduledoc """
  NBPR package for [`kmod`](https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git)
  — the Linux kernel module tools (`insmod`, `modprobe`, `modinfo`, `depmod`,
  `lsmod`, `rmmod`) and their `libkmod` library.

  Stock Nerves systems ship busybox's `modprobe` but no `insmod`, so an
  out-of-tree `.ko` staged in a package's priv dir can't be loaded by path.
  Any package declaring `kernel_modules:` must depend on this one —
  `NBPR.Runtime.load_kernel_module!/2` resolves `insmod` and `modinfo` from
  this package's priv dir at boot. It's equally usable standalone: the tools
  land on `PATH` via `NBPR.Application`'s env setup.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "kmod",
    description: "Kernel module loading tools (insmod, modprobe, depmod) and libkmod",
    homepage: "https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git",
    build_opts: [
      tools: [
        type: :boolean,
        default: true,
        br_flag: "BR2_PACKAGE_KMOD_TOOLS",
        doc:
          "Install the module utilities (depmod, insmod, lsmod, modinfo, modprobe, rmmod) alongside libkmod. Required for `kernel_modules:` loading — only disable if you want libkmod alone."
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
