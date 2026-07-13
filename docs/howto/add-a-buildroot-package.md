# How to add a Buildroot package to NBPR

This guide takes you from "I want some upstream binary in my Nerves
rootfs" to "the binary is published as `:nbpr_<name>` in the `nbpr` Hex
organisation". It assumes you know what Nerves and Buildroot are, can
build a Nerves firmware, and have a clone of this repo.

This guide covers **mainline** Buildroot packages, scaffolded with
`mix nbpr.new` (which reads metadata from a mainline Buildroot tree). If
the package isn't in upstream Buildroot, see
[Vendored (out-of-tree) packages](#vendored-out-of-tree-packages) at the
end — you ship a `buildroot/` external tree with the package instead.

## Prerequisites

- A clone of [`jimsynz/nbpr`](https://github.com/jimsynz/nbpr).
- Elixir 1.16+ and OTP 27+.
- A Nerves target you can build against (`rpi4`, `bbb`, etc. — pick one
  you have hardware for, or use `qemu_arm` for a host-only smoke test).
- Docker installed locally if you're not on Linux. The source-build path
  uses the canonical Nerves build container.

## 1. Confirm the package is in upstream Buildroot

Open `deps/nerves_system_br/` after `mix deps.get` and check
`package/<name>/`:

    ls deps/nerves_system_br/package/<name>/

You should see at minimum a `<name>.mk` and a `Config.in`. If the
directory doesn't exist, the package isn't in mainline — stop here and
follow the vendored-package guide instead.

## 2. Resolve deps for a target

The generator reads the Buildroot pin from the workspace's `deps/`. Pull
those in:

    MIX_TARGET=rpi4 mix deps.get

Any real target works — pick one that's already in the workspace
`mix.exs` `deps()`. The first run downloads ~50 MB of Buildroot source
into `~/.local/share/nerves/nbpr/`; subsequent `mix nbpr.new` runs reuse
the cache.

## 3. Scaffold the package

Run the generator with the upstream Buildroot package name (no `nbpr_`
prefix — the generator adds it):

    mix nbpr.new <name>

This creates `packages/nbpr_<name>/` with:

- `mix.exs` — version, licence, description, dependency on `:nbpr` and
  any auto-detected `:nbpr_*` siblings already in the workspace.
- `lib/nbpr/<name>.ex` — the package's metadata module, doing
  `use NBPR.BrPackage`.
- `README.md` — stub with upstream description and links.
- `test/` — a smoke test asserting the metadata is well-formed.

The generator pre-fills the upstream version, SPDX-validated licences,
homepage, and description directly from the Buildroot tree. You don't
edit those by hand.

If a Buildroot licence string isn't a valid SPDX identifier (e.g.
`GPL-2.0+`), the generator stops and prints suggestions. Re-run with
`--licenses "GPL-2.0-or-later"` to override.

## 4. Review auto-detected sibling dependencies

The generator parses the upstream package's `_DEPENDENCIES` and
`select BR2_PACKAGE_*` directives. For each dep it finds:

- If `packages/nbpr_<dep>/` already exists in the workspace, the dep is
  added to the new package's `mix.exs` automatically.
- If not, the generator prints a warning listing the unresolved deps.

You decide what to do with each unresolved dep:

- **Provided by the base Nerves system** (`ncurses`, `openssl`, `zlib`,
  `libc`, etc.) — ignore. They're already in the rootfs.
- **Not provided by base, not yet packaged in NBPR** — go scaffold them
  too, recursively. `mix nbpr.new <dep>` for each, then come back and
  add them to your package's deps via the same `nbpr_dep/2` helper.

## 5. Declare daemons, kernel modules, and build options

Open `lib/nbpr/<name>.ex`. The default scaffold gives you:

```elixir
defmodule NBPR.<Name> do
  @moduledoc "..."

  use NBPR.BrPackage,
    version: 1,
    br_package: "<name>",
    description: "...",
    artifact_sites: [{:ghcr, "ghcr.io/<owner>/<repo>"}]
end
```

Extend it as the package needs. The full option schema is in
`NBPR.BrPackage`'s moduledoc. The common extensions are:

- **Daemons** (the package runs a long-lived process like `dnsmasq`) —
  add a `daemons:` declaration. See `NBPR.BrPackage`'s moduledoc for
  the schema; `:nbpr_dnsmasq` is the canonical example.
- **Kernel modules** (out-of-tree `.ko` files) — add a `kernel_modules:`
  declaration, and add `:nbpr_kmod` to the package's deps (it ships
  the `insmod`/`modinfo` tools that stock Nerves systems lack). The
  macro generates an `Application` that loads each module at boot via
  `NBPR.Runtime.load_kernel_module!/2`.
- **Build options** (Buildroot kconfig you want to expose to consumers,
  e.g. `--enable-fips`) — add a `build_opts:` schema. Consumers
  override via their app's `config/target.exs` per target.

Per-extension how-tos for each of these are on the to-do list. For now,
follow the schema in `NBPR.BrPackage`'s moduledoc and copy from an
existing package that does the same thing.

For a basic CLI-tool package (jq, htop, strace), no extra declarations
are needed.

## 6. Build locally to verify

From the workspace root:

    MIX_TARGET=rpi4 mix nbpr.build NBPR.<Name> -o /tmp/build

On first run this pulls the Nerves build container (~1 GB), then runs
Buildroot for the package. Subsequent runs are faster — Buildroot
caches its working tree per target/system-version.

A successful build leaves a `nbpr_<name>-<version>-<system>-<key>.tar.gz`
in `/tmp/build`. If the tarball is there, the package built. If not,
the build runner prints the offending step. Buildroot's per-package
logs live under `~/.local/share/nerves/nbpr/build/<system>-<br-vsn>/`
— `<package>-build.log` and friends usually point at the root cause.

## 7. Smoke-test in a Nerves project

Point a real Nerves project at your local checkout via a path-dep:

```elixir
# In your test Nerves project's mix.exs
defp deps do
  [
    # ...
    {:nbpr, path: "../path/to/nbpr/nbpr"},
    {:nbpr_<name>, path: "../path/to/nbpr/packages/nbpr_<name>"}
  ]
end
```

Then `mix firmware` and deploy. On the device, exercise the binary via
`System.cmd/2` (or, for daemon-bearing packages, confirm the daemon
module is supervised and running).

## 8. Open a PR

Commit conventions (also documented in
[CONTRIBUTING.md](../../CONTRIBUTING.md)):

- Conventional commits: `improvement(packages): add nbpr_<name>`.
- One commit per logical change. Don't squash unrelated work.
- Don't bypass commit hooks.

CI runs the package matrix on push: every (package × target × system
version) is built. If anything fails, the PR shouldn't merge.

## 9. After merge — automatic release

Once your PR lands on `main`:

1. The build matrix runs for the new package. Successful builds publish
   the prebuilt artefact to GHCR.
2. After the build succeeds, the auto-release workflow detects that the
   package's local `@version` is ahead of Hex (because it's brand-new
   on Hex), creates a `nbpr_<name>-v<version>` tag, and dispatches the
   release workflow.
3. The release workflow publishes the package to the `nbpr` Hex
   organisation.

You don't tag or publish manually.

## Common gotchas

- **`host-*` dependencies** are build-host-only. The generator filters
  them out automatically; you shouldn't see them in your generated
  `mix.exs`.

- **Conditional `_DEPENDENCIES += foo`** lines (gated by `ifeq` on
  kconfig) are deliberately skipped by the dep parser — they depend on
  user kconfig choices, not intrinsic package wiring. If your package
  needs one of these unconditionally, declare the sibling dep manually
  in `mix.exs` after scaffolding.

- **Make-variable references** like `$(TARGET_NLS_DEPENDENCIES)` in the
  upstream `_DEPENDENCIES` line aren't resolved statically. Same
  workaround as above if the dep is mandatory.

- **Buildroot versions like `2.91`** aren't valid Hex semver. The
  generator pads to `2.91.0` automatically. Subsequent nbpr-side
  rebuilds of the same upstream version go in the patch position
  (`2.91.1`, `2.91.2`, …).

- **Buildroot package names with hyphens** (e.g. `kernel-modules`) map
  to underscored module names (`NBPR.KernelModules`) and underscored
  Hex package names (`nbpr_kernel_modules`). The generator handles the
  mapping; pass the BR-style hyphenated name to `mix nbpr.new`.

## Vendored (out-of-tree) packages

When the upstream isn't in Buildroot mainline, you ship the Buildroot
recipes yourself as a `BR2_EXTERNAL` tree inside the package, and the
metadata module points at it instead of naming a mainline package.
`:nbpr_hailo8` (the Hailo-8 HailoRT runtime + PCIe driver + firmware) is
the worked example.

Layout — a `buildroot/` dir at the package root:

    packages/nbpr_<name>/
      buildroot/
        external.desc            # name: NBPR_<NAME>
        external.mk              # include $(sort $(wildcard $(BR2_EXTERNAL_NBPR_<NAME>_PATH)/package/*/*.mk))
        Config.in               # source each package's Config.in
        package/<pkg>/{Config.in,<pkg>.mk,<pkg>.hash, *.patch}
        ...
      lib/nbpr/<name>.ex
      mix.exs                    # `files:` must include "buildroot"

The metadata module uses `:br_external_path` + `:br_packages` instead of
`:br_package`:

```elixir
use NBPR.BrPackage,
  version: 1,
  br_external_path: "buildroot",
  # Buildroot packages to build, in dependency order; their per-package
  # outputs are merged into one artefact.
  br_packages: ["spdlog_hailort", "hailort", "hailort-firmware", "hailort-drivers"],
  description: "...",
  kernel_modules: ["hailo_pci"],   # insmod'd from priv at boot (see below)
  expose_staging: true,            # ship headers/libs for a consumer NIF
  targets: [:rpi5],                # restrict the prebuild matrix
  artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
```

Notes specific to vendored packages:

- **One nbpr package → many Buildroot packages.** `:br_packages` lists
  them in dependency order; each is enabled in the defconfig, built, and
  its files-list-filtered output merged. `BR2_EXTERNAL` gets the
  package's `buildroot/` tree appended automatically.
- **Hashes.** Provide a `<pkg>.hash` for each recipe (Buildroot verifies
  downloads). GitHub-archive and S3 blobs are reproducible; compute with
  `sha256sum` on the actual download.
- **Kernel modules** declared in `kernel_modules:` are loaded at boot by
  `insmod`'ing the `.ko` shipped in the package's `priv/` (an out-of-tree
  module won't be in the system's `modules.dep`, so `modprobe` can't find
  it). A kernel-module Buildroot package pulls in and builds `linux`
  automatically — the first source-build is slow, then cached.
- **Firmware** installed under `target/lib/firmware/` is routed to the
  real rootfs (`/lib/firmware`), where the kernel firmware loader looks.
- **`expose_staging: true`** ships the sysroot (headers, dev `.so`,
  CMake/pkg-config) to `priv/staging` so a consumer NIF can
  cross-compile against the shipped library.
- **Set the package app's `mod:`** to the generated
  `NBPR.<Name>.Application` in `mix.exs` so the kmod load runs at boot.

There's no `mix nbpr.new` for vendored packages yet — copy an existing
one (`packages/nbpr_hailo8`) as the template.
