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

## Share custom-system builds through your registry

A custom Nerves system usually needs its own package builds. To share those
builds across developer machines and CI, configure your project's OCI registry
namespace in `config/config.exs`:

```elixir
config :nbpr,
  registry: "forgejo.example.com/my-org/firmware",
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
`forgejo.example.com/my-org/firmware/nbpr_<package>:<build-tag>`. Publishing is disabled
by default; a cache hit does not trigger a push. Push failures fail the task
and leave the packed tarball on disk for retry with `mix nbpr.publish`.
That task also prefers the configured project registry.

For a self-hosted Forgejo registry, set `NBPR_REGISTRY_USERNAME` to your
Forgejo username and `NBPR_REGISTRY_TOKEN` to a personal access token with
package access. Use read access for pulls and write access for publishing.
These credentials are scoped to the configured project registry; upstream
fallbacks do not receive them. Without credentials, pulls are anonymous and
require public packages. Store tokens in your CI secrets or environment.

The registry prefix is `<host>[:port]/<owner>[/<path>]`. HTTPS is the default;
use an explicit `http://` prefix for a local development registry. The OCI
client supports Basic authentication and Bearer token endpoints on the same
origin as the registry, as used by Forgejo. Cross-origin token endpoints,
redirects and upload locations are not currently supported.

You can also set `registry: "ghcr.io/my-org/firmware"` to use the existing
GHCR backend, with `GHCR_TOKEN` (or `GITHUB_TOKEN`) and optional
`GHCR_USERNAME`. GHCR credentials are independent of the project registry's
`NBPR_REGISTRY_*` credentials.

See [Forgejo's container registry documentation](https://forgejo.org/docs/latest/user/packages/container/)
for image naming and token authentication. Package authors can declare an
OCI source directly with `artifact_sites: [{:oci, "forgejo.example.com/owner/path"}]`.

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
