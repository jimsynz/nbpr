defmodule NBPR.Libsocketcan do
  @moduledoc """
  NBPR package for
  [`libsocketcan`](http://git.pengutronix.de/?p=tools/libsocketcan.git;a=summary)
  — Pengutronix's C library for configuring SocketCAN interfaces over netlink.

  Ships `libsocketcan.so.2` under this package's priv dir;
  `NBPR.Application` prepends that directory to `LD_LIBRARY_PATH` at boot so
  sibling packages resolve the soname.

  ## What it's for, and what it isn't

  The library wraps the rtnetlink calls that set and read a CAN interface's
  configuration — `can_set_bitrate/2`, `can_set_bittiming/2`,
  `can_set_ctrlmode/2`, `can_do_start/1`, `can_get_state/2`,
  `can_get_berr_counter/2` and friends. It is the C API for the things `ip
  link set <dev> type can ...` does from a shell.

  **There is no Elixir binding here, and nothing in NBPR links it today.**
  Two reasons to pull it into a firmware:

    * A NIF or port program of yours wants to configure a CAN interface and
      read its error counters without shelling out to `ip`. The artefact
      carries `libsocketcan.h`, `can_netlink.h` and a `.pc` file in its
      staging slice, so the library is linkable at firmware-build time.
    * `:nbpr_socketcand`, when it exists, builds against it for the
      `BR2_PACKAGE_LIBSOCKETCAN` code path — socketcand can then serve
      bitrate and controller-mode changes over its protocol rather than
      refusing them.

  For reading and writing CAN *frames* from Elixir you want neither this nor
  `:nbpr_can_utils` — that's an ordinary `AF_CAN` socket, and the kernel is
  the whole interface.

  ## Kernel requirements

  Everything here is a netlink call against a CAN netdev, so it needs
  `CONFIG_CAN` and `CONFIG_CAN_DEV`, which stock Nerves systems don't enable.
  `NBPR.CanUtils`'s moduledoc has the full list and what to ask a system
  maintainer for.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "libsocketcan",
    description: "C library for configuring SocketCAN interfaces over netlink",
    homepage: "http://git.pengutronix.de/?p=tools/libsocketcan.git;a=summary",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
