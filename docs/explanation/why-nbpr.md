# Why NBPR exists

NBPR (the Nerves Binary Package Repository) exists because there's a
gap between "I want this Linux binary on my Nerves device" and "I have
a Nerves system that ships it". This document explains the gap, why
existing options don't quite close it, and the shape NBPR settled on.

## How Nerves ships binaries today

A Nerves firmware image is a SquashFS rootfs built by Buildroot. The
rootfs is immutable on the device — there's no `apt-get install` at
runtime, by design. Every binary on the device is decided at firmware
build time.

That decision happens in one of three places:

- **The Nerves system layer** (`nerves_system_*`). The system
  maintainer picks the Buildroot package set and configures it.
  Adding a binary here means a fork or an upstream PR, plus
  rebuilding the system.
- **`rootfs_overlay/`**. The user's project can drop arbitrary files
  into the rootfs. Fine for config files; awkward for binaries
  because you have to source them somewhere — typically by
  cross-compiling separately.
- **`mix.exs` `:priv` files** of an Elixir dependency. Some libraries
  ship native binaries this way (e.g. `:exla`'s `XLA` blobs). Works,
  but each library does it ad-hoc, with no shared build, cache, or
  daemon-supervision story.

Each option works for some situations. None of them scale to "I
casually want a small CLI tool on a few of my devices".

## The gap

The Nerves system layer is the canonical place to put a binary, but
it's also the most expensive — every system fork is a branch you have
to maintain across upstream Nerves releases. People only fork when
they have to.

`rootfs_overlay/` is cheap, but it offloads cross-compilation onto
the user. For a binary with non-trivial dependencies, that's a lot of
work to re-do per project.

The middle ground people actually want: "give me jq on this device
without forking the system or hand-rolling a cross-compile". That's
NBPR.

## What NBPR does

NBPR distributes Buildroot-built target binaries as Hex packages. The
mechanics:

- Each binary is a Hex package (`:nbpr_jq`, `:nbpr_dnsmasq`, …) with
  a thin Mix project wrapping a Buildroot external tree.
- The user adds it to their `mix.exs`. `mix nbpr.fetch` (a Mix task
  injected ahead of `mix firmware`) downloads a prebuilt artefact
  from GHCR matching the target/system tuple, and drops the binaries
  into the package's `priv/`.
- At boot, an NBPR application sets `PATH` and `LD_LIBRARY_PATH` so
  the binaries are reachable from any BEAM process.

The system layer doesn't change. The kernel doesn't change. The
firmware build process doesn't change. NBPR layers on top.

When no prebuilt artefact exists for the user's target/system tuple
(e.g. they're on a system version we haven't built against yet),
`mix nbpr.fetch` falls back to running Buildroot locally to build
from source. The same package source produces both paths — there's no
"fast path vs slow path" divergence.

## What NBPR isn't

A few explicit non-goals:

- **Not a runtime package manager.** Nothing about NBPR runs on the
  device — it all happens at firmware build time. The immutable
  rootfs model stays intact.
- **Not a Buildroot replacement.** The system maintainer is still the
  gatekeeper for kernel config, base toolchain, and what's in the
  base rootfs. NBPR adds binaries on top of whatever the system
  ships; it doesn't override or substitute.
- **Not a kernel-config interface.** In-tree kmods that aren't
  enabled in the system's defconfig still need a system PR or fork.
  NBPR can ship out-of-tree kmods (via `kernel_modules:` declarations
  on a package), but it can't ask the kernel to be different.

## Trade-offs we accepted

- **Source-build fallback must stay bullet-proof.** A prebuilt
  artefact won't always exist for every target/system-version
  combination. The source-build path has to work, every time, with
  no one's intervention. That constrains the design — package
  metadata has to encode everything Buildroot needs, and the
  external-tree shape can't drift from upstream conventions.
- **Conflict detection at resolve time.** Two packages requiring
  different Buildroot kconfig options on a shared transitive (e.g.
  one wants OpenSSL with FIPS, one without) can't be satisfied
  simultaneously. NBPR fails loud at resolve time rather than
  letting the user produce a quietly-broken firmware.
- **Org-scoped binaries, public library.** The `:nbpr` library is on
  public hex.pm so its docs land on hexdocs and consumers can install
  via the standard Igniter flow. The binary packages live in a Hex
  organisation primarily to avoid polluting the main hex.pm namespace
  with potentially hundreds of `:nbpr_*` entries — there's no
  good-faith reason a casual hex.pm visitor should see all of them
  scrolling past. The org's public read key opens the gate without
  giving anyone publish rights, so consumers who want binary packages
  can fetch them once they're authenticated. The artefact tarballs
  themselves live on GHCR (free, GitHub-hosted), not in Hex — the
  Hex package is just metadata + Mix project shape.

## When you might still want a system fork instead

- The binary needs kernel changes (config, in-tree kmod, patches).
- The binary needs a different base toolchain or libc.
- You need to ship something *every* device in your fleet has,
  forever — at that scale, the maintenance cost of a forked system
  becomes proportional to the value, and it's the right place for
  the change.

For everything else, NBPR.
