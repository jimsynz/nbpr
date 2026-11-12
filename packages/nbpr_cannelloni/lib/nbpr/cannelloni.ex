defmodule NBPR.Cannelloni do
  @moduledoc """
  NBPR package for [`cannelloni`](https://github.com/mguentner/cannelloni) — a
  SocketCAN-over-Ethernet tunnel.

  Adds the `cannelloni` binary at `/usr/bin/cannelloni` and the
  `libcannelloni-common.so.0` it links, and generates
  `NBPR.Cannelloni.Cannelloni` — a MuonTrap-supervised GenServer the user
  adds to their own supervision tree:

      children = [
        {NBPR.Cannelloni.Cannelloni, can_interface: "can0", remote_address: "10.0.0.2"}
      ]

  It takes frames off a local CAN interface, batches them, and ships them to
  a peer running the same program, which writes them onto its own CAN
  interface — so a device with no CAN controller can work a bus attached to
  one that has. Both ends run cannelloni; there is no separate server.

  See `NBPR.Cannelloni.Cannelloni` for the full runtime option schema.

  ## Transports

  UDP is the default and the one the protocol was designed around: frames
  are batched until `buffer_timeout_us` elapses, then sent as a single
  datagram, so a busy bus costs far fewer packets than one datagram per
  frame. TCP is available via `transport: :tcp_client` / `:tcp_server` when
  something between the peers won't pass UDP.

  **SCTP is not built.** Buildroot gates it on `BR2_PACKAGE_LKSCTP_TOOLS`,
  which would need an `:nbpr_lksctp_tools` package to turn on, and the
  kernel's `CONFIG_IP_SCTP` besides — neither of which any Nerves system
  has. The binary's `-S` flag is compiled out, not merely defaulted off.

  ## Daemon mode is not exposed

  cannelloni's `-f` (fork into background) and `-P` (pid file) are
  deliberately absent from the option schema. cannelloni stays in the
  foreground unless told otherwise, which is exactly what MuonTrap needs —
  forking would hand the GenServer a pid that exits immediately and leave
  the real process unsupervised.

  ## Kernel requirements

  cannelloni opens a raw CAN socket on both ends, so each end needs
  `CONFIG_CAN` and `CONFIG_CAN_RAW` plus a driver for its interface — none
  of which stock Nerves systems enable. `NBPR.CanUtils`'s moduledoc has the
  full list. `CONFIG_CAN_VCAN` is the one to ask for on the end that has no
  controller: a `vcan0` is a perfectly good tunnel endpoint.

  ## C++ runtime

  cannelloni is C++ and links `libstdc++.so.6`. Buildroot's `Config.in`
  makes the package depend on `BR2_INSTALL_LIBSTDCPP`, so a system without
  it can't select cannelloni at all — the failure is a build error in CI,
  not a broken artefact. Of the built system artefacts to hand (rpi0_2,
  rpi4, rpi5, x86_64) every one sets it and carries the library in its
  rootfs, so there's nothing extra to ship.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "cannelloni",
    description: "SocketCAN over Ethernet tunnel",
    homepage: "https://github.com/mguentner/cannelloni",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}],
    daemons: [
      cannelloni: [
        path: "/usr/bin/cannelloni",
        argv_template: {__MODULE__, :argv, []},
        opts: [
          can_interface: [
            type: :string,
            required: true,
            flag: "-I",
            doc:
              "CAN interface to tunnel, e.g. `\"can0\"`. cannelloni's own default is `vcan0`, which is rarely what a device wants."
          ],
          transport: [
            type: {:in, [:udp, :tcp_client, :tcp_server]},
            default: :udp,
            doc:
              "Transport to carry frames over. `:udp` batches frames into datagrams and is the default. `:tcp_client` and `:tcp_server` map onto `-C c` and `-C s`; exactly one peer takes each role."
          ],
          remote_address: [
            type: :string,
            flag: "-R",
            doc:
              "Peer address. Required for `:udp` — cannelloni exits with a usage error without it — and unused by `:tcp_server`."
          ],
          remote_port: [
            type: :integer,
            flag: "-r",
            doc: "Peer port. Unset leaves cannelloni's default of 20000."
          ],
          local_address: [
            type: :string,
            flag: "-L",
            doc: "Address to bind. Unset leaves cannelloni's default of `0.0.0.0`."
          ],
          local_port: [
            type: :integer,
            flag: "-l",
            doc: "Port to bind. Unset leaves cannelloni's default of 20000."
          ],
          buffer_timeout_us: [
            type: :pos_integer,
            flag: "-t",
            doc:
              "How long to batch frames before sending, in microseconds. Unset leaves cannelloni's default of 100000 (100 ms). Lower trades bandwidth for latency; zero is rejected by cannelloni."
          ],
          stale_timeout_us: [
            type: :non_neg_integer,
            flag: "-x",
            doc:
              "Drop a CAN frame that has been undeliverable for longer than this, in microseconds; `0` disables dropping. Unset leaves cannelloni's default of 2000000 (2 s). Matters when the peer goes away: without it the queue grows until the link comes back and then floods the bus with stale frames."
          ],
          timeout_table: [
            type: :string,
            flag: "-T",
            doc:
              "Path to a CSV of per-CAN-ID buffer timeouts, for giving latency-sensitive IDs a shorter batch window than the rest."
          ],
          sort_frames: [
            type: :boolean,
            default: false,
            flag: "-s",
            doc: "Sort frames by CAN ID within each batch before sending."
          ],
          no_peer_check: [
            type: :boolean,
            default: false,
            flag: "-p",
            doc:
              "Accept datagrams from any source rather than only the configured peer. Off by default; turning it on means anything that can reach the port can inject frames onto the bus."
          ],
          ipv6: [
            type: :boolean,
            default: false,
            flag: "-6",
            doc: "Use IPv6 instead of IPv4."
          ],
          mtu: [
            type: :pos_integer,
            flag: "-m",
            doc:
              "Link MTU in bytes. Unset leaves cannelloni's default of 1500. Raise it on a path that carries jumbo frames; lower it where something in between fragments."
          ],
          debug: [
            type: :string,
            flag: "-d",
            doc:
              "Debug categories, as a subset of the letters `cubt` — CAN frames, UDP/TCP frames, internal buffers, internal timers. MuonTrap captures the output into the BEAM logs."
          ]
        ]
      ]
    ]

  @doc """
  Builds cannelloni's argv, expanding `:transport` into its `-C` form.

  cannelloni selects TCP with `-C c`/`-C s` and takes UDP as the absence of
  the flag, which `NBPR.BrPackage.default_argv/2`'s one-flag-per-option
  mapping can't express — so this pops `:transport` off, delegates the rest,
  and prepends the flag pair when there is one.
  """
  @spec argv(keyword(), %{atom() => String.t()}) :: [String.t()]
  def argv(opts, opt_flags) do
    {transport, flagged} = Keyword.pop!(opts, :transport)

    transport_argv(transport) ++ NBPR.BrPackage.default_argv(flagged, opt_flags)
  end

  defp transport_argv(:udp), do: []
  defp transport_argv(:tcp_client), do: ["-C", "c"]
  defp transport_argv(:tcp_server), do: ["-C", "s"]
end
