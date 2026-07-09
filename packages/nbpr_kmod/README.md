# nbpr_kmod

> Kernel module tools (`insmod`, `modprobe`, `depmod`) and `libkmod`
> packaged for Nerves.

[`kmod`](https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git)
packaged for Nerves. Tracks the upstream Buildroot `kmod` package —
this release wraps **34.2**.

Stock Nerves systems ship busybox's `modprobe` but no `insmod`, so an
out-of-tree `.ko` shipped by an NBPR package can't be loaded by path.
Every package declaring `kernel_modules:` depends on this one;
`NBPR.Runtime.load_kernel_module!/2` resolves `insmod` and `modinfo`
from this package's priv dir at boot.

## Usage

Usually pulled in transitively by a kernel-module-bearing package. To
use the tools directly, add to your Nerves project's `mix.exs`:

    {:nbpr_kmod, "~> 34.2", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware` — the tools land under
`<release>/lib/nbpr_kmod-<vsn>/priv/` and `NBPR.Application` adds them
to `PATH` at boot:

    {output, 0} = System.cmd("lsmod", [])

See the [NBPR README](https://github.com/jimsynz/nbpr) for the full
integration flow.

## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_kmod, build_opts: [
      # tools: true — set false for libkmod alone (breaks kernel_modules loading)
    ]
