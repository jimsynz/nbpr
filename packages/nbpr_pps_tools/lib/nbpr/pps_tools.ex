defmodule NBPR.PpsTools do
  @moduledoc """
  NBPR package for [`pps-tools`](https://github.com/redlab-i/pps-tools/) — the
  userspace utilities for the Linux PPS (pulse-per-second) API.

  Adds five binaries under `/usr/bin/`:

    * `ppsfind` — resolve a PPS source name to its `/dev/pps*` device
    * `ppstest` — print timestamps as pulses arrive; the first thing to run
      when checking whether a GPS PPS line is wired up
    * `ppsctl` — query and set a source's fetch/capture parameters
    * `ppswatch` — long-running monitor reporting jitter and offset
    * `ppsldisc` — attach the PPS line discipline to a serial port, which is
      how a GPS receiver's PPS-on-DCD becomes a `/dev/pps*` device

  It also installs `sys/timepps.h` into the sysroot. That header is what
  `:nbpr_gpsd`'s `pps: true` build option is really after — Buildroot gates
  gpsd's `HAVE_SYS_TIMEPPS_H` code path (and its `ppscheck` client) on
  `BR2_PACKAGE_PPS_TOOLS`.

  ## Kernel requirements

  These are userspace tools for a kernel facility, and shipping them doesn't
  enable that facility. The active Nerves system's kernel needs `CONFIG_PPS`
  plus at least one client:

    * `CONFIG_PPS_CLIENT_LDISC` — PPS via a serial port's DCD line, paired
      with `ppsldisc`. The usual route for a UART-attached GPS.
    * `CONFIG_PPS_CLIENT_GPIO` — PPS via a GPIO, paired with a `pps-gpio`
      device-tree overlay. The usual route for a Raspberry Pi GPS HAT.

  Stock Nerves systems don't enable `CONFIG_PPS`, so `/dev/pps*` won't exist
  until the system maintainer turns it on (or you build a fork). Kernel
  configuration is outside NBPR's remit — `ppstest` reporting no such device
  is the expected result on an unmodified system.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "pps-tools",
    description: "Userspace utilities for the Linux PPS (pulse-per-second) API",
    homepage: "https://github.com/redlab-i/pps-tools/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
