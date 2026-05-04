# nbpr

The library underpinning the [NBPR](https://github.com/jimsynz/nbpr)
(Nerves Binary Package Repository) ecosystem — a curated Hex repo for
distributing Buildroot-built target binaries to Nerves firmware
projects. `:nbpr` itself ships only the macros, Mix tasks, and resolver
machinery; the binaries live in sibling `:nbpr_*` packages published to
the `nbpr` Hex organisation.

## What it does

- **`NBPR.BrPackage`** — the macro every `:nbpr_*` package `use`s.
  Validates options against a NimbleOptions schema, generates an
  introspection function (`__nbpr_package__/0`), and (for daemon-bearing
  packages) a nested supervised module per declared daemon.
- **`mix nbpr.fetch`** — runs ahead of `mix firmware`. Walks the user's
  loaded apps for `:nbpr_*` packages, pulls each one's prebuilt artefact
  from GHCR (or source-builds via Buildroot when no prebuild exists),
  and copies the binaries into the package's `priv/` for the OTP release
  to pick up.
- **`NBPR.Application`** — boots on the device, sets `PATH` and
  `LD_LIBRARY_PATH` so the binaries shipped via `priv/` are reachable
  from anywhere in the user's app.
- **`mix nbpr.new <name>`** — scaffolds a new `:nbpr_*` package, reading
  the upstream version, SPDX-validated licences, homepage, and a starter
  description directly from the workspace's pinned Buildroot tree.

## Consumer flow

In your Nerves app's `mix.exs`:

    {:nbpr_jq, "~> 1.0", repo: "nbpr"}

then alias `mix firmware`:

    aliases: ["firmware": ["nbpr.fetch", "firmware"]]

…and run `mix deps.get` + `mix firmware` as usual. The first time, you
need to register the `nbpr` Hex repo:

    mix hex.repo add nbpr https://repo.hex.pm/repos/nbpr \
      --auth-key <hex-org-key>

For daemon-bearing packages (e.g. `:nbpr_dnsmasq`), add the generated
daemon module to your supervision tree — see each package's README and
generated `@moduledoc` for specifics.

## Repo layout

The full source — including the four currently published packages
(`:nbpr_jq`, `:nbpr_dnsmasq`, `:nbpr_htop`, `:nbpr_iperf3`) and the
`nbpr_demo` reference firmware — lives at
<https://github.com/jimsynz/nbpr>.

## Licence

Apache-2.0.
