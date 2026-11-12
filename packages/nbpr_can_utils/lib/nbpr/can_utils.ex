defmodule NBPR.CanUtils do
  @moduledoc """
  NBPR package for [`can-utils`](https://github.com/linux-can/can-utils) — the
  userspace tools for Linux SocketCAN.

  Adds 35 binaries under `/usr/bin/` and `libisobusfs.so` alongside them.
  Nothing here is a daemon in NBPR's sense: they're all short-lived or
  interactive tools you reach for from a console or `System.cmd/3`, so the
  package generates no supervised module.

  ## Raw CAN

  The tools most people mean by "can-utils". They open `PF_CAN`/`CAN_RAW`
  sockets, so they need `CONFIG_CAN_RAW`.

    * `candump` — print frames as they arrive, with filtering, colouring and
      logfile capture. The first thing to run on a bus you don't trust yet.
    * `cansend` — send one frame and exit
    * `cangen` — generate traffic, fixed or random, for soak and load tests
    * `canplayer` — replay a `candump` logfile back onto a bus
    * `canlogserver` — the same capture, written to a TCP socket
    * `cansniffer` — per-ID view that highlights the bytes that changed
    * `canbusload` — bus utilisation, as a percentage, per interface
    * `cansequence` — send an incrementing counter and check it comes back,
      which is how you catch drops
    * `canfdtest` — two-node echo test, also used as a driver conformance check

  ## Log conversion

  `asc2log` and `log2asc` convert between Vector's ASC format and candump's;
  `log2long` rewrites a candump log in a human-readable long form.

  ## Broadcast manager and gateway

    * `bcmserver` — TCP front end to the kernel's broadcast manager, which
      does cyclic transmission and receive filtering in-kernel
      (`CONFIG_CAN_BCM`)
    * `cangw` — configure the in-kernel gateway: routing and frame
      modification between interfaces (`CONFIG_CAN_GW`)

  ## ISO-TP (ISO 15765-2)

  The segmented transport every OBD-II and UDS stack sits on, needing
  `CONFIG_CAN_ISOTP`: `isotpsend` and `isotprecv` for a single PDU,
  `isotpdump` and `isotpsniffer` to decode transfers on the wire,
  `isotpperf` for throughput, `isotptun` for a point-to-point IP tunnel, and
  `isotpserver` as a TCP front end.

  ## SAE J1939

  Heavy-vehicle and marine networking, needing `CONFIG_CAN_J1939`:
  `j1939acd` (address-claiming daemon), `j1939cat` (`cat` over J1939,
  transport protocol included), `j1939spy`, `j1939sr`, `testj1939`, and the
  `j1939-timedate-cli`/`j1939-timedate-srv` pair for the time/date PGN.

  ## ISOBUS-FS (ISO 11783-13)

  `isobusfs-srv` and `isobusfs-cli` — the file server agricultural implements
  use to read and write data on a tractor terminal. Built on J1939, and the
  only part of the package with a shared library: `libisobusfs.so` lands in
  the package's `priv/usr/lib`, which `NBPR.Application` puts on
  `LD_LIBRARY_PATH` at boot.

  ## Serial-line CAN

  `slcand`, `slcan_attach` and `slcanpty` attach a serial CAN adapter — the
  USB dongles that speak the LAWICEL/SLCAN ASCII protocol — as a `slcanN`
  interface. Needs `CONFIG_CAN_SLCAN`.

  ## Bit timing and controller debug

  `can-calc-bit-timing` computes controller register values for a given clock
  and bitrate; `mcp251xfd-dump` decodes a coredump from an MCP251xFD
  controller.

  ## Kernel requirements

  These are userspace tools for a kernel subsystem, and shipping them doesn't
  enable that subsystem. **Stock Nerves systems don't enable `CONFIG_CAN`** —
  verified against the built rpi0_2, rpi4 and rpi5 artefacts, none of whose
  `modules.builtin` carries anything under `net/can`. There is no `can0` to
  configure and no `PF_CAN` to bind until the system maintainer turns it on
  (or you build a fork). The minimum is:

    * `CONFIG_CAN` — the protocol family
    * `CONFIG_CAN_RAW` — raw sockets, which `candump` and `cansend` use
    * `CONFIG_CAN_DEV` — the netdev half, and what makes the bitrate
      settable from `ip link`
    * a controller driver — `CONFIG_CAN_MCP251X` for the MCP2515 SPI HATs,
      `CONFIG_CAN_MCP251XFD` for MCP2517FD/MCP2518FD, `CONFIG_CAN_FLEXCAN`
      on i.MX, `CONFIG_CAN_C_CAN_PLATFORM` for the BeagleBone's D_CAN

  Each protocol family above is a separate symbol, and the matching tools
  fail at `socket(2)` with `EPROTONOSUPPORT` when it's missing rather than
  anywhere more informative. `CONFIG_CAN_VCAN` is worth asking for too: a
  virtual interface is how you exercise all of this without wiring up
  hardware.

  An SPI CAN HAT on a Raspberry Pi needs a device-tree overlay as well —
  `dtoverlay=mcp2515-can0,oscillator=16000000,interrupt=25` or similar in
  `config.txt`, with the oscillator and interrupt matching the board. Like
  the kernel config, that lives in the Nerves system and is outside NBPR's
  remit.

  ## Bringing an interface up

  No extra package needed. Nerves builds busybox with
  `CONFIG_FEATURE_IP_LINK_CAN`, so the stock rootfs already configures CAN
  interfaces and `iproute2` isn't required:

      System.cmd("ip", ~w[link set can0 type can bitrate 500000])
      System.cmd("ip", ~w[link set can0 up])
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "can-utils",
    description: "Userspace tools for Linux SocketCAN",
    homepage: "https://github.com/linux-can/can-utils",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
