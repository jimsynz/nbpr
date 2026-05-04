# How to add a Buildroot package to NBPR

This guide takes you from "I want some upstream binary in my Nerves
rootfs" to "the binary is published as `:nbpr_<name>` in the `nbpr` Hex
organisation". It assumes you know what Nerves and Buildroot are, can
build a Nerves firmware, and have a clone of this repo.

If the package isn't in upstream Buildroot mainline, this flow won't
work — `mix nbpr.new` reads metadata from a mainline Buildroot tree.
A vendored-package guide is on the to-do list; for now, treat
out-of-tree packages as out of scope here.

## Prerequisites

- A clone of [`nerves-project/nbpr`](https://github.com/nerves-project/nbpr).
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
  declaration. The macro generates an `Application` that runs
  `modprobe` for each at boot.
- **Build options** (Buildroot kconfig you want to expose to consumers,
  e.g. `--enable-fips`) — add a `build_opts:` schema. Consumers
  override via `Mix.Config` per target.

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
