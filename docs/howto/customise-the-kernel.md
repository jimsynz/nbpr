# How to customise the Linux kernel in a Nerves project

This guide takes you from "the stock Nerves kernel doesn't have the option I
need" to a firmware running your own rebuilt kernel — without forking the
Nerves system. It's for the author of a Nerves *application*, not an nbpr
package maintainer.

`nbpr_linux` rebuilds the kernel your system already ships — same version, same
vendor source — with your `.config` fragments and patches layered on, then
injects the result at `mix firmware` time. The Nerves system you depend on is
left untouched.

Reach for this when you need a kernel option the system maintainer didn't
enable (an extra netfilter target, a filesystem, WireGuard, a USB gadget mode)
or a small out-of-tree patch. If the change belongs upstream — a new board, a
kernel version bump — it belongs in a Nerves system PR or fork instead.

## Prerequisites

- A Nerves project you can already build firmware for, on a target nbpr
  supports (e.g. `rpi4`).
- `mix nbpr.fetch` wired to run before `mix firmware`. The nbpr installer sets
  this up; if you added nbpr by hand, ensure your `mix.exs` has:

  ```elixir
  aliases: [firmware: ["nbpr.fetch", "firmware"]]
  ```

- Docker installed, unless you build inside `mix nerves.system.shell`. The
  kernel is built in the canonical Nerves build container, the same as every
  other nbpr package.

## 1. Add the dependency

Add `nbpr_linux` for the target(s) you want a custom kernel on:

```elixir
# mix.exs
{:nbpr_linux, "~> 0.1", targets: [:rpi4], organization: "nbpr"}
```

There's no kernel version in the dependency — `nbpr_linux` always rebuilds the
version your Nerves system pins. The same line works for every target; the
per-target customisation lives in config (next step).

Run `mix deps.get` with your target set:

    MIX_TARGET=rpi4 mix deps.get

## 2. Write a config fragment

A fragment is a partial kernel `.config` — just the symbols you want to change,
one per line. Put it anywhere in your project; `config/linux/` is a tidy home:

```
# config/linux/extras.fragment
CONFIG_WIREGUARD=m
CONFIG_NETFILTER_XT_TARGET_LOG=y
```

Buildroot merges the fragment over the system's kernel config and reconciles
the result, so you only list what you're changing — dependencies of the symbols
you enable are pulled in automatically.

To find the right symbol names, browse the kernel's own config interactively:

    MIX_TARGET=rpi4 mix nerves.system.shell
    # inside the shell:
    make linux-menuconfig      # search with "/", note the CONFIG_* names

Set the symbols you want there, then either copy the `CONFIG_*` lines into your
fragment or use the diff `menuconfig` shows against the saved config. Keep the
fragment minimal — the smaller the delta, the easier it is to review and
re-base on a future system bump.

## 3. (Optional) Add a patch

For source changes — a backported fix, a vendor patch — drop a standard unified
diff alongside the fragment:

```
# config/linux/0001-fix-something.patch
```

Patches are applied on top of whatever the system already applies (some boards,
like the BeagleBone, ship their own kernel patches); yours are added, not
substituted.

## 4. Point `nbpr_linux` at your fragment and patches

Declare them in your target config. Paths are relative to the project root:

```elixir
# config/target.exs
config :nbpr_linux,
  config_fragments: ["config/linux/extras.fragment"],
  patches: ["config/linux/0001-fix-something.patch"]
```

Both keys are optional and both take lists. Per-target differences fall out of
the normal `MIX_TARGET`-based config split — there's only one `:nbpr_linux`
dependency regardless of how many targets use it.

## 5. Build the firmware

    MIX_TARGET=rpi4 mix firmware

The first build rebuilds the kernel, which takes a while (minutes, not
seconds — it's a real kernel compile). Subsequent builds are instant *unless
you change a fragment or patch*: the build is cached against the contents of
your fragment and patch files, so editing one triggers a rebuild and touching
anything else doesn't.

What happens under the hood, for reference:

- `mix nbpr.fetch` rebuilds the kernel with your customisation.
- The in-tree modules are shipped through the standard rootfs overlay.
- The kernel image and device trees are injected via a shadow system directory
  that `NERVES_SYSTEM` is pointed at — your global Nerves artefact cache is
  never modified, so other projects on the same machine are unaffected.

## 6. Verify

Deploy the firmware and check the running kernel reflects your change. For a
config symbol that surfaces at runtime, the most direct check is on the device:

    # e.g. a module you enabled now loads:
    cmd("modprobe wireguard && lsmod | grep wireguard")

Or confirm the kernel was rebuilt at all — its build timestamp will be recent:

    cmd("uname -a")

If a change doesn't take, re-check the symbol name in `linux-menuconfig`
(a typo'd `CONFIG_*` is silently ignored by the merge) and confirm the fragment
path in `config/target.exs` is correct — a missing file fails the build with a
clear error, but a wrong-but-present file just won't do what you expect.

## Gotchas

- **The kernel version is fixed to the system's.** `nbpr_linux` can't move you
  to a different kernel version — that's the system maintainer's call. It only
  re-configures and re-patches the version you already have.

- **Out-of-tree kernel-module packages** (other `nbpr_*` packages that declare
  `kernel_modules:`) are built against the *stock* system's kernel headers. If
  your config changes alter the kernel's module ABI, those modules may fail to
  load until rebuilt against your kernel. In-tree modules shipped by
  `nbpr_linux` itself are always consistent.

- **A kernel bump in the system invalidates your build,** as it should — you'll
  get a fresh rebuild on the next `mix firmware`, and a patch that no longer
  applies will fail loudly. Re-base the patch against the new version.

- **Build host.** Off `mix nerves.system.shell`, the build runs in Docker; on a
  machine without Docker it'll fail with a clear message. Inside the dev shell
  it builds natively.
