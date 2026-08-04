# nbpr_ncurses

> Terminal-handling library for curses-style TUI programs.

[`ncurses`](https://invisible-island.net/ncurses/) packaged for Nerves. Tracks the upstream Buildroot `ncurses` package — this release wraps the **6.6** snapshot series.

Buildroot builds ncurses from a dated snapshot (`NCURSES_VERSION` is
`6.6-20251231` at the pinned Buildroot release), which is neither a Hex
version nor something Renovate's `buildroot-package` datasource can read
from the `.mk`. So this package tracks `NCURSES_VERSION_MAJOR` alone, and
rebuilds against a newer snapshot of the same major bump the patch
position: `6.6.1`, `6.6.2`, and so on.

Licence: X11-distribute-modifications-variant — the ncurses licence, which
SPDX identifies by that name and references ncurses' own `COPYING`. (Not
`MIT-advertising`, which despite the name is the Enlightenment e16 licence.)


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_ncurses, "~> 6.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.


## You probably only need this on a non-RPi target

Every Raspberry Pi Nerves system already carries ncurses: its
`nerves_defconfig` enables `alsa-utils`, whose Kconfig `select`s ncurses.
So on `rpi0`, `rpi0_2`, `rpi3`, `rpi3a`, `rpi4` and `rpi5` an
ncurses-linking package resolves its soname against the base system's
staging and this package adds nothing.

On `bbb`, `x86_64` and `qemu_aarch64` nothing pulls ncurses in. There, a
package that wants it — `:nbpr_gpsd` with `ncurses: true`, for its `cgps`
and `gpsmon` clients — needs this one in the firmware too, since an nbpr
artefact only carries its own Buildroot files-list, not its dependencies'.


## Terminfo

Buildroot installs only a handful of vital terminfo entries, so a curses
program run over SSH with an unlisted `TERM` (`xterm-256color`,
`tmux-256color`, `alacritty`, ...) fails to initialise. Add what you need
in `config/target.exs` rather than making callers export `TERM=vt100`:

    config :nbpr_ncurses, build_opts: [
      additional_terminfo: "x/xterm-256color t/tmux-256color"
    ]

Each entry carries its single-letter path prefix.


## Wide characters

`wchar` defaults to `false`, matching Buildroot and the RPi systems' base
ncurses. Turning it on changes the library sonames to the `w` variants
(`libncursesw.so.6`), which a consumer built against plain ncurses won't
resolve against — and a consumer's own build (`:nbpr_gpsd` with
`ncurses: true`, say) sets only `BR2_PACKAGE_NCURSES`, so it links
`libncurses.so.6`. Enabling `wchar` here without also arranging for the
consumer to be built wide will strand it.

Source: <https://github.com/jimsynz/nbpr>.
