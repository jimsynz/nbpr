# nbpr_linux

> Rebuilds the Nerves system's Linux kernel with extra config and patches.

Unlike the other `nbpr_*` packages, `nbpr_linux` ships no binary of its own.
It rebuilds the **kernel your Nerves system already uses** — same version, same
vendor source — with your `.config` fragments and source patches layered on,
then injects the result into the firmware. The shared Nerves system artefact is
never modified.

## Usage

In your Nerves project's `mix.exs`, add it for the target(s) you want:

    {:nbpr_linux, "~> 0.1", targets: [:rpi4], organization: "nbpr"}

Declare your customisation in target config (e.g. `config/target.exs`):

    config :nbpr_linux,
      config_fragments: ["config/linux/wireguard.fragment"],
      patches: ["config/linux/0001-vendor-fix.patch"]

Paths are relative to your project root. Then build as usual:

    mix deps.get
    mix firmware

`mix nbpr.fetch` (wired before `mix firmware`) rebuilds the kernel, ships the
in-tree modules through the rootfs overlay, and points `NERVES_SYSTEM` at a
shadow system directory carrying the rebuilt kernel image and device trees.

## How it works

- **Version is pinned to the system.** The system's `nerves_defconfig` is reused
  verbatim, so `BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION` is untouched — you get
  exactly the kernel the system maintainer shipped, just rebuilt with your
  additions. There's no version to choose, and the same dep works on every
  target.
- **Config fragments** become `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`; Buildroot
  merges them over the system's kernel `.config` and reconciles non-interactively.
- **Patches** become `BR2_LINUX_KERNEL_PATCH`, *merged* with any the system
  already applies (so e.g. a board's vendor patches are preserved, not clobbered).
- **The cache key** hashes your fragment and patch file *contents*, so editing a
  fragment forces a rebuild while moving your project directory does not.

## Caveats

- **A kernel build takes a while.** Rebuilding the kernel is minutes, not
  seconds — it runs on the first `mix firmware` after a config/patch change and
  is cached by content thereafter. Builds run in the `nerves_system_br`
  container (or natively inside `mix nerves.system.shell`), like every other
  nbpr package, so Docker is required off the dev shell.
- **Out-of-tree kernel-module packages** (other `nbpr_*` packages declaring
  `kernel_modules:`) are compiled against the system's stock kernel headers. If
  your config changes alter the kernel's module ABI, those will need rebuilding.
