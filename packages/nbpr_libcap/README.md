# nbpr_libcap

> Userspace interface to POSIX 1003.1e capabilities.

[`libcap`](https://sites.google.com/site/fullycapable/) packaged for Nerves. Tracks the upstream Buildroot `libcap` package — this release wraps **2.78**.

Licences: GPL-2.0-only, BSD-3-Clause.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_libcap, "~> 2.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.

Usually you won't add this directly — it arrives as a dependency of a
package that links it.


## Why it exists

No Nerves system ships libcap. Checked against the built system artefacts at
their pinned versions — `rpi0` 2.1.0, `rpi4` 2.1.0, `rpi5` 2.1.0, `bbb`
2.30.0, `x86_64` 1.34.0 and `qemu_aarch64` 0.4.0 — none has
`libcap.so.2` in staging.

Buildroot's chrony `select`s libcap unconditionally, so `chronyd` always
links it, and an nbpr artefact only carries its own Buildroot files-list.
Hence `:nbpr_chrony` depends on this package. Several other Buildroot
packages select libcap the same way, so expect more consumers over time.


## Capabilities on Nerves

The BEAM runs as root on a Nerves target, so nothing here is needed to
*grant* privilege — it's already total. libcap matters because daemons
written to drop privilege link against it whether or not they end up
dropping anything.

The `tools` option (`setcap`, `getcap`, `getpcaps`, `capsh`) is off by
default for the same reason. `setcap` also wants kernel xattr and
security-label support plus a writable filesystem to set attributes on,
neither of which describes a squashfs Nerves rootfs. Turn it on in
`config/target.exs` if you need them:

    config :nbpr_libcap, build_opts: [tools: true]

Source: <https://github.com/jimsynz/nbpr>.
