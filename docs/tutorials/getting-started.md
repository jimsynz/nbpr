# Getting started with NBPR

This tutorial walks you through installing NBPR in a fresh Nerves
project, pulling in `jq` from the binary catalogue, and calling it
from your BEAM application running on a real device.

By the end, you'll have a Nerves device that boots, has `jq`
available, and lets your application shell out to it. About 15 minutes
of reading + a coffee while the firmware builds.

## What you need

- Elixir 1.16+ and OTP 27+ installed.
- The Nerves toolchain installed. If you've not done this before,
  follow [Nerves' Installation
  guide](https://hexdocs.pm/nerves/installation.html) first — come
  back here once `mix nerves.new` works for you.
- A Raspberry Pi 4 (we'll target `rpi4` throughout). If you have
  different hardware, substitute its target alias wherever `rpi4`
  appears.
- An SD card and a way to write to it (`mix burn` handles the
  details).

## Step 1: create a fresh Nerves project

    mix nerves.new my_nbpr_app
    cd my_nbpr_app

The generator creates a working Nerves application with no extra
dependencies. We'll layer NBPR on top.

## Step 2: install NBPR

    mix igniter.install nbpr

This does three things in one shot:

- Adds `{:nbpr, "~> 0.2"}` to your project's `deps/0`.
- Adds `firmware: ["nbpr.fetch", "firmware"]` to your project's
  `aliases/0`, so `mix firmware` runs `mix nbpr.fetch` first to pull
  prebuilt binaries from GHCR.
- Authenticates your local Hex client to the `nbpr` Hex organisation
  using its publicly-shared read key, so subsequent `mix deps.get`
  calls can fetch `:nbpr_*` packages.

Igniter shows you the diff and asks for confirmation. Accept it.

## Step 3: add a binary package

Open `mix.exs` and add `:nbpr_jq` to your deps:

```elixir
defp deps do
  [
    {:nerves, "~> 1.10", runtime: false},
    {:nbpr, "~> 0.2"},
    {:nbpr_jq, "~> 1.0", organization: "nbpr"},
    # ... whatever else mix nerves.new generated
  ]
end
```

Note the `organization: "nbpr"` clause on `:nbpr_jq`. The library
itself lives on public hex.pm, but the binary packages are scoped to
the `nbpr` organisation — that's the gate `mix igniter.install`
authenticated you against in step 2.

## Step 4: build the firmware

    export MIX_TARGET=rpi4
    mix deps.get
    mix firmware

`mix deps.get` fetches the dependencies. `mix firmware` runs the
NBPR-injected `mix nbpr.fetch` step first, which checks GHCR for a
prebuilt `jq` artefact matching your target and system version. If
one exists (it does — `rpi4` is a published target), it gets pulled
and dropped into the package's `priv/`. Then the standard Nerves
firmware build runs on top.

The first run takes a few minutes — most of it is the regular Nerves
build, not the NBPR fetch. Subsequent runs are faster.

## Step 5: burn and boot

Insert your SD card and:

    mix burn

The Pi will boot. Wait ~30 seconds, then connect — over IEx-on-target
(`mix.exs` has the SSH config), or `ssh nerves.local` if your project
includes `:nerves_ssh`.

## Step 6: use jq from your application

In an IEx session on the device:

    iex(1)> System.cmd("jq", [".name", "/etc/os-release"], stderr_to_stdout: true)
    {"...", 0}

That's it — `jq` is on the device's `PATH`, callable from any BEAM
process. NBPR's `Application` module sets `PATH` and
`LD_LIBRARY_PATH` at boot so the binaries shipped via `priv/` are
findable from anywhere in your app.

For something more interesting, write a JSON file and pipe it
through:

    iex(2)> json = ~s({"hostname": "pi4", "uptime": 3600})
    iex(3)> File.write!("/tmp/x.json", json)
    iex(4)> System.cmd("jq", [".hostname", "/tmp/x.json"])
    {"\"pi4\"\n", 0}

You now have a working NBPR-backed Nerves device.

## What to read next

- **[How to add a Buildroot package to NBPR](../howto/add-a-buildroot-package.md)** — if
  the binary you want isn't in the catalogue and you'd like to add it.
- **[Why NBPR exists](../explanation/why-nbpr.md)** — the problem
  space and why NBPR's shape is the way it is.
- **[How NBPR composes with Buildroot](../explanation/packaging-model.md)** —
  the runtime model: prebuilt artefacts, source-build fallback, daemon
  supervision, kernel-module loading.
- **`NBPR.BrPackage`** in the [API reference](https://hexdocs.pm/nbpr) —
  if you want to understand the macro every package uses.
