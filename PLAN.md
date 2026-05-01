# NBPR Spike Plan

**Status:** Phases 1, 2, 3 (priv-mode), 4.1–4.6, 5, 6.1–6.2 complete. Source-build path validated end-to-end on macOS host across rpi4/rpi5/bbb. `mix nbpr.fetch` falls back to source-build when no prebuilt artefact is published, auto-shimming the system source from GitHub for users on Hex `nerves_system_*` deps. CI matrix builds + publishes (package × target × system_version) to GHCR, currently covering `:nbpr_jq` and `:nbpr_dnsmasq` for the eight popular Nerves systems (rpi0, rpi0_2, rpi3, rpi3a, rpi4, rpi5, bbb, x86_64). Hex publish workflow drafted but pending first tag (`mix hex.publish` → public Hex.pm for `:nbpr` library, `nbpr` org for `:nbpr_*` packages). Phase 6.3 (QEMU smoke test) outstanding.
**Last updated:** 2026-05-01

## Hex publish bootstrap (one-time)

Required setup before tagging the first release:

1. Hex.pm `nbpr` organisation exists with the publishing user as a member
   (paid hex.pm org subscription).
2. `HEX_API_KEY` GitHub Actions secret is set, owned by a user with publish
   access to the `nbpr` org.
3. Publish order matters — `:nbpr_*` packages depend on `:nbpr`, so tag
   `nbpr-v0.1.0` first to land the library on public Hex.pm, then tag
   `nbpr_jq-v1.8.1` etc. to publish to the `nbpr` org.

NBPR (Nerves Binary Package Repository) is a curated Hex repository for distributing Buildroot-built target packages to Nerves firmware projects. A user's app declares `{:nbpr_jq, "~> 1.0", repo: "nbpr"}` and gets the binary in their rootfs at firmware build time, with optional MuonTrap supervision wrappers for daemon-bearing packages.

This plan covers a spike to validate the design end-to-end with two trivial packages before tackling anything stateful.

## Goals

- Validate the artefact resolve + source-build mechanic end-to-end.
- Prove the `NBPR.BrPackage` macro shape with one daemonless package and one daemon-bearing package.
- Expose any seams in `Nerves.Artifact` that need adapting to support a third party-class artefact.

## Non-goals (for the spike)

- Production polish, full board matrix, performance tuning.
- Kernel-module-bearing packages — out-of-tree kmods (zfs, wireguard, etc.) are regular `:nbpr_*` packages with a `kernel_modules:` metadata field, but deferred until the userspace path is solid.
- Kernel rebuild support — explicitly out of scope. The system maintainer remains the gatekeeper of kernel config.
- Vendored (not-in-mainline-BR) packages — schema supports them, no spike package exercises them.
- Multi-daemon packages — one daemon per package for now.

## Workspace layout

Single git repo `nbpr/`. Flat-monorepo pattern, like Ash's. Not an umbrella — the shared lockfile and joint publish semantics fight against per-package independent versioning on Hex.

```
nbpr/
├── mix.exs                       # workspace root: tooling deps only, no compile
├── README.md
├── CLAUDE.md
├── PLAN.md
├── .github/workflows/
│   ├── ci.yml                    # per-package compile + test
│   └── build-artifacts.yml       # matrix: (package x system x system-version)
├── nbpr/                         # the library
│   ├── lib/
│   │   ├── nbpr.ex
│   │   ├── nbpr/br_package.ex    # the `use` macro
│   │   ├── nbpr/build_runner.ex  # source-build path
│   │   ├── nbpr/artifact.ex      # cache-key, fetch, layout
│   │   └── nbpr/mix_helpers.ex   # mix firmware hook
│   ├── mix.exs
│   └── test/
├── packages/
│   ├── nbpr_jq/
│   │   ├── lib/nbpr/jq.ex        # defmodule NBPR.Jq
│   │   ├── mix.exs               # app: :nbpr_jq, deps: [:nbpr]
│   │   ├── buildroot/            # only present when not in mainline BR
│   │   └── test/
│   └── nbpr_dnsmasq/             # second package, has a daemon
└── scripts/
    └── publish-all.exs           # walk packages/, publish in topo order
```

A package whose binary is in mainline Buildroot doesn't need its own `buildroot/` fragment — it just declares "use BR's `jq` with these CONFIGs". A package shipping something not in mainline BR ships an external-tree fragment.

## Phasing

### Phase 0 — confirmed spike packages

- **Daemonless:** `:nbpr_jq` (module `NBPR.Jq`). Small, mainline BR, useful in firmware. Validates the simplest path: declare → build → overlay → present in rootfs.
- **Daemon-bearing:** `:nbpr_dnsmasq` (module `NBPR.Dnsmasq` with daemon `NBPR.Dnsmasq.Dnsmasq`). Real use case (Nerves devices serving DHCP/DNS for first-boot hotspot), modest options surface, mainline BR, BEAM doesn't already do this. Validates MuonTrap generation + nested daemon module shape.

### Phase 1 — `nbpr` library skeleton

**Deliverables:**
- `NBPR.BrPackage` macro: parses `use` opts via NimbleOptions, generates `__nbpr_package__/0`, no daemon code yet.
- `Mix.Tasks.Nbpr.Inspect` — prints metadata for a given package. Useful for debugging the macro before any build path exists.
- `Mix.Tasks.Nbpr.New` — `mix nbpr.new <name>` scaffolds `./packages/nbpr_<name>/` (mix.exs with `app: :nbpr_<name>`, `lib/nbpr/<name>.ex` containing `defmodule NBPR.<Camel> do; use NBPR.BrPackage, ... end`, README, test stub). Owns the package-name → module-name mapping so authors never camelize manually.
- Package metadata struct: name, version, build_opts schema, br_package_name (mainline) or br_external_path (vendored), runtime/sysroot artefact split, daemons (empty list ok), kernel_modules (empty list ok).
- Schema versioning: include a `version: 1` field in the metadata struct from day one. Cheap insurance for the curated CI to introspect across mixed-version packages.

**Risks/unknowns:**
- NimbleOptions can't natively express "this option is forbidden when X is true" (mutually-exclusive build opts). May need post-validation hook. Not blocking for spike.

### Phase 2 — `:nbpr_jq` end-to-end without source build

**Deliverables:**
- `NBPR.Jq` module using `NBPR.BrPackage`, scaffolded via `mix nbpr.new jq`.
- Manually-built artefact tarball uploaded to a GitHub release on the nbpr repo.
- Fetch path: `mix deps.get` resolves the package; `nbpr` artefact resolver downloads the tarball based on system + system-version.

Validates the resolve path before the build path. Cheaper to debug.

**Risks/unknowns:**
- Hex repo registration UX: user has to `mix hex.repo add nbpr ...` first. Document it; possibly a `mix nbpr.setup` task later.
- `Nerves.Artifact` is currently structured around `:system` and `:toolchain` types. May need a `:nbpr_package` type or a parallel resolver. Read `lib/nerves/artifact.ex` early to decide.

### Phase 3 — `mix firmware` hook

**Deliverables:**
- Compile-time scan of dep graph for nbpr packages.
- For each, fetch (or in-source-build, later) the artefact.
- Pass artefact directories as additional `-a` overlay args to `rel2fw.sh` (already supported, no change needed to `nerves_system_br`).
- Conflict checker: refuse if two nbpr deps disagree on a shared transitive option.

**Risks/unknowns:**
- `-a` overlay precedence: order matters when multiple packages want to write to the same path. Need a deterministic ordering rule (topo-sorted by deps, alphabetical as tiebreaker). Document and stick to it.
- Licence aggregation: leave a slot in the artefact format for `legal-info/` and concatenate in this phase, even if just appending to a file. Don't punt.

### Phase 4 — source-build runner

**Architecture (post-investigation):**

Leverage the user's `deps/nerves_system_br/` rather than inventing our own
BR-tree management. After `mix deps.get`, the user's project tree contains:

- `create-build.sh` with `NERVES_BR_VERSION=<x.y.z>` — the canonical version pin
- `scripts/download-buildroot.sh` — upstream BR fetcher with Nerves mirror fallback
- `patches/buildroot/` — Nerves-specific patches we **must** apply (otherwise nbpr packages build against incompatible upstream BR)
- `external.desc`, `external.mk`, `Config.in`, `package/` — Nerves' BR external tree

So the source-build flow becomes:

1. `NBPR.Buildroot.nerves_system_br_path/0` → `deps/nerves_system_br/`
2. `NBPR.Buildroot.br_version/1` → e.g. `"2025.11.3"`
3. Cache-or-download BR source to `$NERVES_DATA_DIR/nbpr/buildroot/<version>/`
4. Apply `patches/buildroot/*.patch` once when first downloaded
5. Per-build: `make O=<tmp> BR2_DL_DIR=<shared> BR2_EXTERNAL_NBPR=<pkg-tree> ... <pkg>-rebuild`
6. Harvest from `O=<tmp>/per-package/<pkg>/target/` (and `staging/`, `legal-info/`)
7. Hand off to `NBPR.Pack`

**Deliverables:**
- ~~`Mix.Tasks.Nbpr.Build`~~ Built incrementally — see Phase 4.x sub-phases.
- Sets `BR2_EXTERNAL_NBPR_*` to the package's BR external tree (or none if mainline-BR).
- Applies the package's `build_opts` as `BR2_PACKAGE_*` settings.
- `make <pkg>-rebuild`, harvest from per-package output dir, hand off to `NBPR.Pack`.

**Sub-phases:**
- 4.1 ✅ Discovery (`NBPR.Buildroot`) — paths, BR version, patches list.
- 4.2 ✅ BR source caching (`NBPR.Buildroot.Source`) — download tarball, apply patches, store at `$NERVES_DATA_DIR/nbpr/buildroot/<version>/`.
- 4.3 ✅ Build invocation on Linux:
  - Part 1: Defconfig rendering (`NBPR.Buildroot.Defconfig`).
  - Part 2: `make` runner (`NBPR.Buildroot.Build`) — `make olddefconfig` + `make <pkg>-rebuild` with live output streaming.
- 4.4 ✅ Output harvesting (`NBPR.Buildroot.Harvest`) — locates per-package `target/` and `staging/`, returns `Pack.sources()` map.
- 4.5 ⏸ Docker wrapper for non-Linux hosts.
- 4.6 ✅ `Mix.Tasks.Nbpr.Build` — top-level user-facing task that wires all the pieces together. Currently Linux-only; needs 4.5 for macOS.

**Caching constraints (binding):**

Buildroot is huge. Every part of the source-build path that *can* be shared *must* be:

- **BR source tree** is downloaded once per BR version into `$NERVES_DATA_DIR/nbpr/buildroot/<br_version>/` and treated as read-only thereafter. Every nbpr build for that BR version mounts/uses the same tree.
- **BR download cache** (`dl/`) lives at `$NERVES_DATA_DIR/nbpr/buildroot-dl/` and is shared across builds and BR versions. Source tarballs are never invalidated; the cache just accumulates.
- **Per-build outputs** use BR's `O=<dir>` and `BR2_PER_PACKAGE_DIRECTORIES=y` so individual package builds don't share output state, can be wiped at will, and never contend with each other or the shared source tree.

**Risks/unknowns:**
- Buildroot per-package output dir mode is supposed to make this clean but has known sharp edges with packages that touch shared `target-finalize` hooks. Probably fine for `jq`; deliberate test on something stateful before declaring victory.
- Docker requirement: same as system builds today, so not a new burden, but document explicitly.
- BR-version discovery: pinned by the system's `nerves_system_br` dep version. Need a reliable way to map `nerves_system_br x.y.z` → BR version (`BR_VERSION` from its `mix.exs` or the BR source tarball URL).

### Phase 5 — `:nbpr_dnsmasq` with daemon module generation

**Deliverables:**
- Macro generates `NBPR.Dnsmasq.Dnsmasq` (nested module, `child_spec/1`, runtime NimbleOptions validation).
- Generated `@moduledoc` + `@doc` from option schemas via `NimbleOptions.docs/1`.
- Generated `@spec` declarations from option types where NimbleOptions supports it.
- User's app: `{NBPR.Dnsmasq.Dnsmasq, [config_file: "/etc/dnsmasq.conf"]}` in their supervision tree.

**Risks/unknowns:**
- Daemon naming/transform: pick a transform (`Macro.camelize` handles dashes) and document.
- Process lifecycle: dnsmasq forks by default; needs `--keep-in-foreground` for MuonTrap to supervise correctly. This is a per-daemon concern that the package author has to know — not all daemons "just work" under MuonTrap. Document this expectation in `NBPR.BrPackage`.

### Phase 6 — CI and Hex publish

**Deliverables:**
- Per-package CI: compile, test, build artefact for the prebuild matrix, publish to GitHub Releases.
- Per-package Hex publish on tag (manual gate on first releases).
- Workspace-level CI for cross-package lints (no two packages declare conflicting global BR options without flagging).

**Risks/unknowns:**
- Matrix size: even minimal (rpi4 + x86_64) × (current + N-1 system version) × N packages is non-trivial CI minutes. Acceptable for spike; revisit if it gets unwieldy.
- Hex publish needs API tokens for the `nbpr` org — bootstrapping step.

## Phase 2 lessons (post-spike notes)

Things learned during Phase 2 worth flagging for future phases:

- **Tarball flat layout matters.** macOS' default `tar` writes AppleDouble `._*` metadata files alongside real entries, which breaks our "single top-level directory" invariant. Stub-build scripts and any future `Pack` users must use `COPYFILE_DISABLE=1 tar` (or stick to `:erl_tar`, which doesn't have the issue).
- **`:inets.start/0` not `Application.ensure_all_started(:inets)`.** The latter brings up the application but not the default httpc profile, so `:httpc.request/4` crashes looking for `:http_util` on some OTP versions. The Erlang-style direct start does both. Captured in the GitHubReleases resolver.
- **Mix tasks don't auto-start the host project's apps.** A Mix task that needs a runtime app (like inets) has to explicitly start it; relying on `extra_applications` only works once the host project's `Application.start` callback has fired.
- **Path deps work cleanly across the workspace and surrounding repos.** `:nbpr` from `../../nbpr/nbpr`, `:nerves` from `../../nerves` (on the upstream branch), `:nbpr_jq` from `../../nbpr/packages/nbpr_jq` — all resolved without surprises.

## Cross-cutting decisions already made

- **Hex package prefix:** all nbpr packages are `:nbpr_*` (e.g. `:nbpr_jq`, `:nbpr_dnsmasq`, `:nbpr_zfs`). No separate kmod prefix; out-of-tree kernel-module packages are regular `:nbpr_*` packages whose metadata declares `kernel_modules: [...]`. The prefix earns its keep on paste-safety: a user dropping `repo: "nbpr"` from their dep gets a clean "no such package" rather than fetching the wrong thing from mainline.
- **Module naming:** Hex package `:nbpr_<name>` → metadata module `NBPR.<Camel>` (e.g. `:nbpr_dnsmasq` → `NBPR.Dnsmasq`). Daemons are always nested even when the name duplicates: daemon `dnsmasq` in `:nbpr_dnsmasq` → `NBPR.Dnsmasq.Dnsmasq`. The `mix nbpr.new` generator emits the module name explicitly, so the standard `Macro.camelize` mapping (which would yield `NbprDnsmasq`) doesn't apply and package authors never have to think about it.
- **Daemons go under user supervision via MuonTrap.** Generated daemon modules expose `child_spec/1`; the user adds them to their own supervision tree. The package's Application module (if any) does not auto-start daemons.
- **Kernel-module packages auto-load via Application.** Packages declaring `kernel_modules: [...]` in their metadata get a generated `NBPR.<Name>.Application` whose `start/2` runs `modprobe` for each declared module at boot. Gated on Nerves target detection (no-op on host so `mix test` and dev workflows are unaffected). `Application.stop/1` is a no-op — kmods are global resources; never `rmmod`. modprobe is idempotent and resolves its own dep graph, so we don't need to load transitive kmods explicitly. This is kmod-only — daemons stay user-supervised.
- **Build options:** configured via `Mix.Config` in the user's app; per-target overrides supported via the existing Nerves `target.exs` pattern. Resolved options contribute to the artefact cache key.
- **Source-build fallback:** mandatory and bullet-proof. Prebuilt artefacts are an optimisation for popular (system, system-version, default-options) tuples; any deviation falls to source-build.
- **Conflict policy:** two packages requiring conflicting BR options on a shared transitive must fail loudly at resolve time. Buildroot's global config can't satisfy both.
- **Licence aggregation:** every package artefact ships its own `legal-info/` slice; firmware build concatenates them.
- **Reuse the system's BR tree:** don't vendor BR per package. Find the system's BR tree via the dep graph at build time.

## Open questions to resolve during spike

- Exact shape of `NBPR.BrPackage` `use` opts (locked once `:nbpr ~> 1.0` ships).
- Should runtime/sysroot artefacts be one tarball with two prefixes, or two separate tarballs? Lean towards one tarball with `target/` and `staging/` top-level dirs, mirroring Buildroot's own layout.
- How to express "this build option requires kernel CONFIG_X". Manifest-only declaration with hard fail-loud at preflight, no kernel rebuild.
- Whether to build a `mix nbpr.check` task as part of Phase 3 or defer.
