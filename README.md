# NBPR

**Nerves Binary Package Repository** — a curated Hex repo for distributing
Buildroot-built target binaries to Nerves firmware projects. Declare
`{:nbpr_jq, "~> 1.8"}` in your app's `mix.exs` and the
binary lands in your rootfs at firmware-build time. Daemon-bearing packages
additionally generate MuonTrap-supervised modules you add to your supervision
tree.

## Quickstart

In a Nerves project:

    mix igniter.install nbpr

Then add the binary packages you need to `mix.exs` and run `mix firmware`
as usual. The full consumer flow, including a step-by-step worked example,
lives in the [Getting Started tutorial](https://nbpr.hexdocs.pm/getting-started.html).

## Moving off the `nbpr` Hex organisation

Before `:nbpr` 0.7.0, the `:nbpr_*` packages were published to a private
`nbpr` Hex organisation, opened to everyone by a shared read key. A Hex
security incident in November 2026 revoked the organisation's keys,
including that shared one, and from then on nobody could fetch the
packages. Rather than hand out a new key, NBPR now publishes every
package to public hex.pm, under the same names and versions.

If your project still declares `organization: "nbpr"` on its deps, run:

    mix igniter.upgrade nbpr
    mix deps.get

The upgrade removes `organization: "nbpr"` from your deps and unlocks
every package `mix.lock` resolved from the organisation.

`mix igniter.upgrade` has to resolve your existing deps before it can
run anything. On a machine that has never fetched the organisation's
packages, that fails, so make the change by hand instead:

1. Delete `organization: "nbpr"` from each `:nbpr_*` dep in `mix.exs`,
   and make sure your `:nbpr` requirement allows 0.7 (`~> 0.7`).
2. Unlock the packages and fetch them again:

       mix deps.unlock $(grep -o '^  "nbpr_[a-z0-9_]*"' mix.lock | tr -d ' "')
       mix deps.get

The read key is still in your machine's Hex config. It's useless now,
so you can remove it:

    mix hex.organization deauth nbpr

The git tags from the organisation era (`nbpr_<name>-v<version>`) are
left as they were. They mark the source that went to the organisation.
The hex.pm release of the same version was published later, from newer
source.

## Documentation

The doc site at [nbpr.hexdocs.pm](https://nbpr.hexdocs.pm) is organised by
intent ([Diátaxis](https://diataxis.fr/)):

- **Tutorials** — learning-oriented walkthroughs.
  [Getting started](https://nbpr.hexdocs.pm/getting-started.html) takes
  you from a fresh Nerves project to a device with `jq` working.
- **How-to guides** — task-oriented recipes. Currently:
  [Add a Buildroot package to NBPR](https://nbpr.hexdocs.pm/add-a-buildroot-package.html).
- **Reference** — the [catalogue](https://nbpr.hexdocs.pm/catalogue.html)
  of available binary packages, plus moduledocs and Mix-task docs in the
  API reference.
- **Explanation** — [Why NBPR exists](https://nbpr.hexdocs.pm/why-nbpr.html)
  and [How NBPR composes with Buildroot](https://nbpr.hexdocs.pm/packaging-model.html).

## Contributing

PRs welcome. The headline contributor task is "add a new Buildroot
package to the catalogue" — see [CONTRIBUTING.md](CONTRIBUTING.md) and
the [How to add a Buildroot package](docs/howto/add-a-buildroot-package.md)
guide.

## Workspace layout

```
nbpr/
├── nbpr/                # the `:nbpr` library (published to public hex.pm)
├── packages/            # one mix project per `:nbpr_*` binary package
├── docs/                # Diátaxis-organised guides; published to hexdocs
├── mix.exs              # build harness (pulls in :nerves + target systems)
└── CONTRIBUTING.md
```

The workspace `mix.exs` pulls in `:nerves` plus whichever `:nerves_system_*`
matches `MIX_TARGET`, so source-builds and the metadata generator have a
real Nerves environment to resolve against.

## Licence

Apache-2.0.
