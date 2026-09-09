# nbpr

The library underpinning the [NBPR](https://github.com/jimsynz/nbpr)
(Nerves Binary Package Repository) ecosystem — a curated Hex repo for
distributing Buildroot-built target binaries to Nerves firmware
projects. `:nbpr` itself ships only the macros, Mix tasks, and
resolver machinery; the binaries live in sibling `:nbpr_*` packages
published to the `nbpr` Hex organisation.

## Quickstart

In a Nerves project:

    mix igniter.install nbpr

Then add the binary packages you need to your deps and run
`mix firmware`. Full walkthrough in
[Getting started](getting-started.md).

## Share custom-system builds through GHCR

A custom Nerves system usually needs its own package builds. To share those
builds across developer machines and CI, configure your project's GHCR
namespace in `config/config.exs`:

```elixir
config :nbpr,
  registry: "ghcr.io/my-org/firmware",
  publish_after_build: System.get_env("NBPR_PUBLISH_AFTER_BUILD") == "1"
```

`mix nbpr.fetch` and `mix nbpr.build` search this namespace before the
package's declared sites, using the existing package/system/version/options
cache key. A registry miss falls back to the package's sites and then a
source build. An existing extracted local cache still takes precedence in
`nbpr.fetch`.

Set `NBPR_PUBLISH_AFTER_BUILD=1` in builds that should populate the shared
cache. Both an explicit `nbpr.build` and a source-build fallback from
`nbpr.fetch` then push the newly packed tarball to
`ghcr.io/my-org/firmware/nbpr_<package>:<build-tag>`. Publishing is disabled
by default; a cache hit does not trigger a push. Push failures fail the task
and leave the packed tarball on disk for retry with `mix nbpr.publish`.
That task also prefers the configured project registry.

Private pulls and pushes use `GHCR_TOKEN`, falling back to `GITHUB_TOKEN`,
with `GHCR_USERNAME` defaulting to `oauth`. Supply credentials in the build
environment with access to the destination packages: read access for pulls,
write access for publishing. Without a token, pulls are anonymous and the
packages must be public. Do not put tokens in package metadata or committed
configuration.

This configuration currently supports GHCR namespaces only, including nested
paths such as `ghcr.io/my-org/firmware`. Other OCI registry hosts are not yet
supported.

## Where to go next

Documentation is organised by intent ([Diátaxis](https://diataxis.fr/)):

- **Tutorials** — [Getting started](getting-started.md).
- **How-to guides** —
  [Add a Buildroot package to NBPR](add-a-buildroot-package.html).
- **Reference** — [Catalogue](catalogue.html) of available binary
  packages, plus the Mix-task and module reference in the API docs.
- **Explanation** — [Why NBPR exists](why-nbpr.md) and
  [How NBPR composes with Buildroot](packaging-model.md).

## Source

[github.com/jimsynz/nbpr](https://github.com/jimsynz/nbpr) — the
`:nbpr` library lives at `nbpr/`; the binary packages live at
`packages/nbpr_*/`.

## Licence

Apache-2.0.
