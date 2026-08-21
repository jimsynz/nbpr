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
directory doesn't exist, look one level deeper before concluding the
package isn't in mainline:

    ls -d deps/nerves_system_br/package/*/<name>/

Some packages live under a parent directory — `fftw-single` under
`fftw`, every `xlib_*` under `x11r7`, the `qt5*` and `gst1-*` families.
Those are still mainline packages and NBPR builds them, but the
generator can't look their metadata up; see step 3. If neither path
exists, the package isn't in mainline — stop here and follow the
vendored-package guide instead.

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

CI builds what the diff implies. A new package directory means your
package is built for every target in the workspace `@prebuild_systems`
map; a library change instead takes smoke coverage across all packages on
one target. If anything fails, the PR shouldn't merge.

The full cross-product isn't what a diff runs, but it does still fit: the
build fans out as a two-level matrix, one outer slice per target and an
inner matrix of that target's packages. GitHub caps a *single job's*
strategy at 256 configurations, and each slice is its own job with its own
budget, so the ceiling is targets × packages rather than a flat 256 — it
won't need revisiting as packages are added.

To rebuild everything from scratch, dispatch the `build` workflow with
`full` set; narrow it with the `target` or `package` inputs for less. An
oversized single slice would still fail the run at strategy-evaluation
time, which produces no failing *check* and so slips past branch
protection, and `mix nbpr.matrix` refuses to emit one for that reason.

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

- **Packages nested under a parent directory** (`package/fftw/fftw-single/`)
  can't be scaffolded by lookup — the generator reads `package/<name>/`
  and will tell you there's no such Buildroot package. Scaffold with
  `mix nbpr.new <name> --no-lookup --br-package <br-name>` and fill in
  the version, licences, homepage and description by hand from the
  package's `.mk` and `Config.in`. Note that a nested `.mk` often
  defines its version as a reference to the parent's
  (`FFTW_SINGLE_VERSION = $(FFTW_VERSION)`), so the literal you want is
  usually in the parent's `.mk` — and that's the file Renovate has to
  track too. The build side needs nothing extra: the kconfig symbols
  gating a nested package are derived from the Buildroot tree at
  defconfig-render time. `:nbpr_fftw_single` is the worked example.

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

- **Packages that load files from a path fixed at build time** won't find
  them. nbpr installs a package's `target/` files under its own `priv/`,
  and only `PATH`, `LD_LIBRARY_PATH` and declared `runtime_env` are
  rewritten to match — anything that `dlopen`s or `opendir`s a compiled-in
  absolute path is looking at a rootfs location nbpr never populated.
  Check the upstream `.mk` for a `--with-*-dir` or `libdir`-derived path
  before assuming a package works. Where the path is configurable at
  runtime, `runtime_env:` covers it (`:nbpr_iptables` redirects
  `XTABLES_LIBDIR` into its priv dir that way). Where it isn't,
  `:nbpr_libao` is the worked example of the limitation: its output plugins
  live under `/usr/lib/ao/plugins-4` with no override, so only libao's
  built-in drivers work. Fixing that case needs the plugin directory
  installed at its rootfs path via the `rootfs/` artefact slice, which
  `NBPR.Pack` carries but the Buildroot harvest step doesn't populate yet.
