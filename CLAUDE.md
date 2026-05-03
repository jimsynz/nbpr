# NBPR — Claude/agent context

## What this is

NBPR (Nerves Binary Package Repository) is a curated Hex repository for distributing Buildroot-built target packages to Nerves firmware projects. Users declare `{:nbpr_jq, "~> 1.0", repo: "nbpr"}` in their app's `mix.exs` and the binary lands in their rootfs at firmware-build time. Packages with daemons additionally generate MuonTrap-supervised GenServer modules the user adds to their supervision tree. Packages bearing out-of-tree kernel modules generate an `Application` that auto-loads them at boot via `modprobe`.

See `PLAN.md` for current status, outstanding work, and Hex publish bootstrap.

## Scope

In scope:
- Userspace Buildroot packages (binaries, libraries, configs) overlaid onto the rootfs.
- A small Elixir library (`:nbpr`) providing the `NBPR.BrPackage` macro that every package `use`s.
- Per-package mix projects published independently to the `nbpr` Hex org.
- Source-build fallback when no prebuilt artefact exists for the active (system, system-version, build-options) tuple. Bullet-proof by requirement, not aspiration.
- Out-of-tree kernel modules (post-spike) — these are regular `:nbpr_*` packages with a `kernel_modules:` metadata field, not a separate prefix. The macro generates an `Application` that loads them at boot.

Out of scope:
- Replacing Buildroot. Nerves' system layer (`nerves_system_*`) stays as is. NBPR layers on top.
- Modifying the kernel config or rebuilding the kernel. The system maintainer remains the gatekeeper of kernel config; in-tree kmods that aren't already enabled require a system PR or fork.
- Runtime package management (no `apt-get` on device). The Nerves immutable-rootfs / A/B model is preserved.

## Workspace layout

Flat monorepo, not an umbrella:

- `mix.exs` (root) — the **build-harness** Mix project. Pulls in `:nerves`, the `nerves_system_*` deps for every target we want to build for, and every `packages/nbpr_*/` as a path dep. `mix nbpr.build` runs from here so `Nerves.Env.system/0` resolves and the `NBPR.<Camel>` modules are loadable. Not a Nerves application, not user-facing — just a tooling shim.
- `nbpr/` — the library: `NBPR.BrPackage` macro, build runner, artefact resolver, `mix firmware` hook.
- `packages/<name>/` — one mix project per package, depending on `:nbpr`. Mainline-BR packages are thin wrappers; vendored packages ship a `buildroot/` external-tree fragment.
- `scripts/` — cross-package orchestration (publish, lint).
- `.github/workflows/` — per-package CI plus the prebuild artefact matrix.

## Building a package locally

From the workspace root, with `MIX_TARGET` set:

    MIX_TARGET=rpi4 mix deps.get
    MIX_TARGET=rpi4 mix nbpr.build NBPR.Jq -o /tmp/jq-built

The harness pulls in `:nerves` and `:nerves_system_<target>` so the Mix
task's `Nerves.Env.system/0` lookup succeeds. Add new target systems to
the `deps/0` list in the workspace `mix.exs` as packages need them.

## Naming conventions

- **Hex package prefix:** all packages are `:nbpr_*` (e.g. `:nbpr_jq`, `:nbpr_dnsmasq`, `:nbpr_zfs`). No separate kmod prefix — out-of-tree kernel-module packages are regular `:nbpr_*` packages whose metadata declares `kernel_modules: [...]`. The prefix earns its keep on paste-safety: a user who copies a dep without `repo: "nbpr"` gets a clean "no such package" error instead of silently fetching something else from mainline.
- **Module namespace:** `:nbpr_<name>` → metadata module `NBPR.<Camel>` (e.g. `:nbpr_dnsmasq` → `NBPR.Dnsmasq`). Daemons are always nested even when the name duplicates: `NBPR.Dnsmasq.Dnsmasq`. The standard `Macro.camelize` mapping (which would yield `NbprDnsmasq`) does not apply — the `mix nbpr.new` generator emits `defmodule NBPR.<Camel> do` directly, so authors never camelize manually.

## Key design decisions (and why)

- **`use NBPR.BrPackage` macro.** Idiomatic Elixir (`Ash.Resource`, `Ecto.Schema` pattern). NimbleOptions for compile-time schema validation. The macro generates `__nbpr_package__/0` (introspection), one nested daemon module per declared daemon (with `child_spec/1`, runtime opts validation, MuonTrap argv assembly), `@moduledoc`/`@doc` from `NimbleOptions.docs/1`, and cache-key contributors.
- **Build options live in the user's `Mix.Config`.** Per-target overrides via the existing Nerves `target.exs` pattern. Resolved options contribute to the artefact cache key — changing options invalidates prebuilt artefacts and falls to source-build.
- **Reuse the system's Buildroot tree.** Don't vendor BR per package. The source-build path discovers the system's BR via the dep graph (`nerves_system_rpi4` → `nerves_system_br`) and invokes it with `BR2_EXTERNAL_NBPR_*` set to the nbpr package's external tree.
- **Conflict detection at resolve time.** Two packages requiring conflicting BR options on a shared transitive (e.g. `:nbpr_openssl` with `fips: true` from one consumer, `fips: false` from another) must fail loudly. Buildroot's global config can't satisfy both.
- **Daemons go under user supervision via MuonTrap.** Not via erlinit pre-run hooks, and not auto-started by the package's Application. The user adds `{NBPR.Dnsmasq.Dnsmasq, opts}` to their own supervision tree. Keeps the BEAM as the single supervisor of truth, preserves user composition (custom restart strategies, conditional starts, per-target opts).
- **Kernel-module packages auto-load via Application.** Packages declaring `kernel_modules: [...]` in their metadata get a generated `NBPR.<Name>.Application` whose `start/2` runs `modprobe` for each at boot, gated on Nerves target detection (no-op on host). `Application.stop/1` is a no-op — kmods are global; never `rmmod`. This is kmod-only — daemon packages do *not* auto-start.
- **`mix firmware` hook via overlay args.** Collect nbpr artefact directories and pass as additional `-a` overlay paths to `rel2fw.sh`. No change needed to `nerves_system_br`. Topo-sorted by deps, alphabetical tiebreaker.
- **Licence aggregation.** Every package artefact ships its own `legal-info/` slice; firmware build concatenates. Designed in from day one to avoid breaking artefact compat later.
- **Schema versioning.** Metadata struct includes a `version: 1` field from day one. The `NBPR.BrPackage` Hex semver dependency is the primary safety net (every package depends on `{:nbpr, "~> 1.0"}`), but the metadata version lets the curated CI introspect across mixed-version packages without parsing source.

## Relationship to surrounding repos

This workspace sits next to the rest of the Nerves project at `~/Dev/github.com/nerves-project/`:

- `../nerves/` — the Nerves Elixir library; defines `Nerves.Package.Platform` and `Nerves.Artifact.BuildRunner` behaviours and the `mix firmware` task. NBPR's hook integrates here.
- `../nerves_system_br/` — Buildroot integration, ships `rel2fw.sh`, `merge-squashfs`, `nerves_env.exs`, the build-container approach NBPR's source-build path reuses.
- `../nerves_system_*/` — per-board systems. NBPR artefacts are matrix-built per (system, system-version).

When investigating Nerves internals, prefer reading these directly over guessing — the codebase is small and well-organised.

## Working in this repo

- When picking up work, check `PLAN.md` for current status and outstanding items.
- Frank Hunleth and James Harton are the primary design collaborators on this — significant design changes warrant a chat, not a unilateral spike.
