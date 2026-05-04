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
