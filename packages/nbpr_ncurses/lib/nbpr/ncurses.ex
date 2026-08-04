defmodule NBPR.Ncurses do
  @moduledoc """
  NBPR package for [`ncurses`](https://invisible-island.net/ncurses/) — the
  terminal-handling library that curses-style TUI programs link against.

  Ships `libncurses`/`libform`/`libmenu`/`libpanel` and a terminfo database
  under this package's priv dir; `NBPR.Application` prepends it to
  `LD_LIBRARY_PATH` at boot so sibling packages resolve the sonames.

  ## You probably only need this on a non-RPi target

  Every Raspberry Pi Nerves system already carries ncurses, because its
  `nerves_defconfig` enables `alsa-utils`, whose Kconfig `select`s ncurses.
  So on `rpi0`/`rpi0_2`/`rpi3`/`rpi3a`/`rpi4`/`rpi5` an ncurses-linking
  package resolves its soname against the base system's staging and this
  package adds nothing.

  On `bbb`, `x86_64` and `qemu_aarch64` nothing pulls ncurses in, so a
  package that wants it — `:nbpr_gpsd` with `ncurses: true`, for its `cgps`
  and `gpsmon` clients — needs this one in the firmware too. An nbpr artefact
  only carries its own Buildroot files-list, not its dependencies'.

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
