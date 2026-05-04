# How NBPR composes with Buildroot

This document describes how an NBPR package goes from source in this
repository to a binary running on a user's Nerves device. It's
structural — the *what* and *why* of each piece — rather than a
recipe. For step-by-step contributor instructions, see [How to add a
Buildroot package to NBPR](../howto/add-a-buildroot-package.md).

## A package is a Buildroot external tree

Each NBPR package is a small Mix project that contains:

- A metadata module (`NBPR.<Pkg>` doing `use NBPR.BrPackage`) — the
  source of truth for the package's name, version, daemons, kernel
  modules, and build options.
- A Buildroot external tree under either `buildroot/` (for vendored,
  out-of-tree packages) or — for mainline packages — *no tree at all*,
  because NBPR introspects the system's Buildroot via `mix nbpr.new`
  and references the upstream package directly.

The external-tree shape is what Buildroot calls `BR2_EXTERNAL` —
documented at length in [Buildroot's
manual](https://buildroot.org/downloads/manual/manual.html#outside-br-custom).
NBPR doesn't reinvent this; it leans on it.

The metadata module is what makes NBPR feel Elixir-shaped. Compile-time
schema validation (via NimbleOptions), an introspection function
(`__nbpr_package__/0`) that build tools and the runtime can read, and
generated supervised modules per declared daemon — the same idiomatic
pattern as `Ash.Resource` or `Ecto.Schema`.

## Two paths to the user's rootfs: prebuilt and source-build

When a Nerves project does `mix firmware`, NBPR's injected
`mix nbpr.fetch` step runs first. For each `:nbpr_*` package in the
loaded apps:

1. Compute the cache key from the inputs (package version, system app,
   system version, build options).
2. Resolve the GHCR tag for that key.
3. **HEAD** the manifest. If it returns 200, the prebuilt artefact
   exists.
4. **Get** the layer blob. The tarball lands in the package's `priv/`.

If step 3 returns 404, fall through to source-build:

1. Run Buildroot locally — natively on Linux inside `mix nerves.system.shell`,
   or via the Nerves canonical build container otherwise.
2. The package's external tree is wired in via
   `BR2_EXTERNAL_NBPR_<NAME>`.
3. Buildroot builds the package against the active system's pinned
   Buildroot version, producing the same tarball Buildroot would have
   produced if the package had been part of the system's defconfig.
4. The tarball goes into the package's `priv/`, same as the prebuilt
   path.

Both paths produce byte-identical output for the same inputs. That's
deliberate — the cache key encodes everything that affects the
artefact, so a prebuilt is by definition "what we'd have built".

## The cache-key model

Published artefacts are immutable. Re-publishing the same key is
either a no-op (same content) or a bug (different content for the
same key, which means our key inputs are missing something).

Inputs that go into the key:

- Package name and version.
- System app and system version (e.g. `nerves_system_rpi4@1.30.0`).
- Resolved build options (after defaults applied).
- The package's external tree contents (hashed).

Inputs that *don't* go into the key:

- The build host. We rely on the canonical Nerves build container to
  make Buildroot reproducible across hosts.
- Network state (mirrors, etc.). Buildroot validates SHAs on every
  download.

If a contributor needs to break a published artefact open and
re-publish, they bump the package's `@version` (one of the inputs), and
the new version gets its own cache key. The old artefact stays where
it is, untouched.

## Composition with the user's BEAM application

Once a binary is in `priv/`, it's just a file shipped inside an OTP
release. NBPR's `Application` module sets `PATH` and `LD_LIBRARY_PATH`
at boot — every package's `priv/usr/bin` ends up on `PATH`, every
package's `priv/usr/lib` ends up on `LD_LIBRARY_PATH`. From the
user's BEAM application:

    System.cmd("jq", [".name", "/etc/os-release"])

works, no path twiddling required.

For packages that ship daemons (long-lived processes like `dnsmasq`),
the `daemons:` declaration in the metadata module generates a nested
supervisable module. The user adds it to their own supervision tree:

    children = [
      {NBPR.Dnsmasq.Dnsmasq, config_file: "/etc/dnsmasq.conf"}
    ]

The generated module is a thin wrapper around MuonTrap — it assembles
the argv from validated options, finds the binary via
`:code.priv_dir/1`, and supervises it as an OS process. We
deliberately don't auto-start daemons via `Application.start/2` or
erlinit pre-run hooks: the user's supervision tree is the single
source of supervisor truth, and conditional starts (per-target,
per-environment) compose naturally there.

For packages that ship kernel modules (out-of-tree `.ko` files), the
`kernel_modules:` declaration generates an `Application` whose
`start/2` runs `modprobe` for each module at boot. This *does*
auto-load — kmods are global, can't be supervised, and "load on every
boot" is the only reasonable behaviour.

## What stays unchanged

The Nerves system layer is untouched. The kernel config is untouched.
The base toolchain is untouched. NBPR adds binaries on top of
whatever the active `nerves_system_*` ships; it never substitutes.

This matters for two reasons:

- **System maintainers stay in charge of system-level decisions.**
  Kernel config, in-tree kmod selection, base libc, build flags that
  affect the whole rootfs — those are still the system maintainer's
  domain. NBPR can't accidentally change them.
- **Upgrading Nerves systems is independent of NBPR.** The user
  bumps their `nerves_system_*` dep; their `:nbpr_*` packages either
  have a prebuilt artefact for the new system version (and it gets
  pulled) or source-build against it (and the resulting artefact is
  cached for next time). No coordination required.

The flip side: NBPR can't fix problems that live below it. If a
binary needs a kernel feature the system hasn't enabled, NBPR can't
help — that's a system-PR or system-fork situation. See [Why NBPR
exists](why-nbpr.md) for where the line is.

## Conflict detection

Two packages requiring different Buildroot options on a shared
transitive can't both be satisfied — Buildroot's global config can't
hold mutually exclusive values. NBPR detects this at resolve time
(during `mix nbpr.fetch`) and fails loudly with the conflicting
specs. The alternative — a quietly-broken firmware where one of the
two packages didn't actually get built with the option it asked for
— is a worse failure mode.

## Licence aggregation

Buildroot tracks every package's licence files. NBPR preserves
that — every artefact tarball ships its own `legal-info/` slice, and
the firmware build concatenates them. This was designed in from day
one rather than retrofitted, because adding licence aggregation later
would have meant breaking artefact compat.

## Schema versioning

The `__nbpr_package__/0` struct includes a `version: 1` field. The
Hex semver dependency on `:nbpr` is the primary safety net — every
package depends on `{:nbpr, "~> 0.X"}`, so an incompatible macro
change forces the package to re-resolve against a compatible major
series. The struct version is a secondary check, useful for tools
that introspect across packages built against different `:nbpr`
versions in a shared workspace.
