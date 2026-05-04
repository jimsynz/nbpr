# NBPR

**Nerves Binary Package Repository** — a curated Hex repo for distributing
Buildroot-built target binaries to Nerves firmware projects. Declare
`{:nbpr_jq, "~> 1.0", organization: "nbpr"}` in your app's `mix.exs` and the
binary lands in your rootfs at firmware-build time. Daemon-bearing packages
additionally generate MuonTrap-supervised modules you add to your supervision
tree.

## Quickstart

In a Nerves project:

    mix igniter.install nbpr

Then add the binary packages you need to `mix.exs` and run `mix firmware`
as usual. The full consumer flow, including a step-by-step worked example,
lives in the [Getting Started tutorial](https://hexdocs.pm/nbpr/getting-started.html).

## Documentation

The doc site at [hexdocs.pm/nbpr](https://hexdocs.pm/nbpr) is organised by
intent ([Diátaxis](https://diataxis.fr/)):

- **Tutorials** — learning-oriented walkthroughs.
  [Getting started](https://hexdocs.pm/nbpr/getting-started.html) takes
  you from a fresh Nerves project to a device with `jq` working.
- **How-to guides** — task-oriented recipes. Currently:
  [Add a Buildroot package to NBPR](https://hexdocs.pm/nbpr/add-a-buildroot-package.html).
- **Reference** — the [catalogue](https://hexdocs.pm/nbpr/catalogue.html)
  of available binary packages, plus moduledocs and Mix-task docs in the
  API reference.
- **Explanation** — [Why NBPR exists](https://hexdocs.pm/nbpr/why-nbpr.html)
  and [How NBPR composes with Buildroot](https://hexdocs.pm/nbpr/packaging-model.html).

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
