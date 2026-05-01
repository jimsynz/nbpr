defmodule NBPR.Dnsmasq do
  @moduledoc """
  NBPR package for [`dnsmasq`](https://thekelleys.org.uk/dnsmasq/doc.html) — a
  lightweight DHCP/DNS server commonly used on Nerves devices to provide
  first-boot hotspot/captive-portal services.

  Adds the `dnsmasq` binary to the rootfs at `/usr/sbin/dnsmasq` and
  generates `NBPR.Dnsmasq.Dnsmasq` — a MuonTrap-supervised GenServer the
  user adds to their own supervision tree:

      children = [
        {NBPR.Dnsmasq.Dnsmasq, config_file: "/etc/dnsmasq.conf"}
      ]

  Most of dnsmasq's behaviour is configured through its config file rather
  than CLI flags, so the daemon's runtime options are deliberately minimal.

  See `NBPR.Dnsmasq.Dnsmasq` for the full option schema.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "dnsmasq",
    description: "Lightweight DHCP/DNS server",
    homepage: "https://thekelleys.org.uk/dnsmasq/doc.html",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}],
    daemons: [
      dnsmasq: [
        path: "/usr/sbin/dnsmasq",
        opts: [
          config_file: [
            type: :string,
            required: true,
            flag: "--conf-file",
            doc: "Path to the dnsmasq config file."
          ],
          keep_in_foreground: [
            type: :boolean,
            default: true,
            flag: "--keep-in-foreground",
            doc:
              "Required `true` for MuonTrap supervision. Disabling will break process tracking."
          ],
          pid_file: [
            type: :string,
            default: "/run/dnsmasq.pid",
            flag: "--pid-file",
            doc: "PID file location. Stored on the writable `/run` tmpfs."
          ],
          log_facility: [
            type: :string,
            default: "-",
            flag: "--log-facility",
            doc: "Log facility (`-` sends to stderr; MuonTrap captures it into the BEAM logs)."
          ]
        ]
      ]
    ]
end
