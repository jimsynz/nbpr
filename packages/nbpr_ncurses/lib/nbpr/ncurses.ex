defmodule NBPR.Ncurses do
  @moduledoc """
  NBPR package for [`ncurses`](https://invisible-island.net/ncurses/) — the
  terminal-handling library that curses-style TUI programs link against.

  Ships `libncurses`/`libform`/`libmenu`/`libpanel` and a terminfo database
  under this package's priv dir; `NBPR.Application` prepends it to
  `LD_LIBRARY_PATH` at boot so sibling packages resolve the sonames.

  ## Nothing currently needs this

  Every Nerves system in the prebuild matrix already ships
  `libncurses.so.6` in its staging — checked directly against the built
  artefacts for `rpi0`, `rpi4`, `rpi5`, `bbb`, `x86_64` and `qemu_aarch64` at
  their pinned versions. So an ncurses-linking package resolves against the
  base system and this one adds nothing today.

  It exists because that isn't a stable guarantee: `nerves_system_rpi4` 2.0.0
  had no ncurses and 2.1.0 does, so it can move the other way too. Nothing in
  a system's `nerves_defconfig` tells you either way — ncurses arrives through
  transitive Kconfig `select`s, so the built system's staging dir is the only
  honest source. If a system version drops it, the package that needs it can
  depend on this one and `NBPR.Artifact.LibCheck` will say so at firmware time
  rather than the device failing to start a binary.

  Don't add it speculatively — an nbpr artefact carries only its own Buildroot
  files-list, so this ships a second copy of a library the base already has.

  ## Terminfo

  Buildroot installs only a handful of vital terminfo entries, so a curses
  program run over SSH with an unlisted `TERM` (`xterm-256color`,
  `tmux-256color`, `alacritty`, ...) fails to initialise. Add the entries you
  need via the `additional_terminfo` build option rather than making callers
  export `TERM=vt100`.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "ncurses",
    description: "Terminal-handling library for curses-style TUI programs",
    homepage: "https://invisible-island.net/ncurses/",
    build_opts: [
      wchar: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_NCURSES_WCHAR",
        doc:
          "Wide-character and UTF-8 support. Changes the library sonames to the `w` variants (`libncursesw.so.6`), so a consumer built against plain ncurses won't resolve against it. Defaults off to match Buildroot and the RPi systems' base ncurses — a consumer package's own build (e.g. `:nbpr_gpsd` with `ncurses: true`) sets only `BR2_PACKAGE_NCURSES`, so it links `libncurses.so.6` and turning this on here would strand it."
      ],
      target_progs: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_NCURSES_TARGET_PROGS",
        doc:
          "Install the terminal utilities (`clear`, `reset`, `tput`, `tset`, `infocmp`, `tic`) alongside the libraries."
      ],
      additional_terminfo: [
        type: :string,
        default: "",
        br_flag: "BR2_PACKAGE_NCURSES_ADDITIONAL_TERMINFO",
        doc:
          "Whitespace-separated terminfo entries to install beyond the vital few, each with its single-letter path prefix — e.g. `\"x/xterm-256color t/tmux-256color\"`."
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
