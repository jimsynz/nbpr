defmodule NBPR.Socketcand do
  @moduledoc """
  NBPR package for [`socketcand`](https://github.com/linux-can/socketcand) —
  a daemon that hands out access to a machine's CAN interfaces over TCP.

  Adds `socketcand` at `/usr/sbin/socketcand` and `socketcandcl` at
  `/usr/bin/socketcandcl`, and generates a MuonTrap-supervised GenServer
  for each. The server is the one most people want:

      children = [
        {NBPR.Socketcand.Socketcand, interfaces: ["can0"], listen_interface: "wlan0"}
      ]

  A client connects, says which bus it wants, and then reads and writes
  frames as lines of ASCII. That makes it the tool of choice when the thing
  that needs the bus isn't on the device — a laptop running
  [python-can](https://python-can.readthedocs.io/)'s `socketcand` backend,
  or anything else that speaks the protocol — and it's how you get at a bus
  from a host that has no CAN hardware of its own.

  See `NBPR.Socketcand.Socketcand` for the full runtime option schema.

  ## The other end

  `NBPR.Socketcand.Socketcandcl` wraps `socketcandcl`, which is the client
  half: it connects to a remote socketcand and mirrors one of *its* buses
  onto a local CAN interface. That makes a bus attached to another machine
  look local — point it at a `vcan0` and anything on this device that
  speaks `AF_CAN` works the remote bus without knowing it's remote.

      children = [
        {NBPR.Socketcand.Socketcandcl,
         server: "10.0.0.2", remote_interface: "can0", local_interface: "vcan0"}
      ]

  It overlaps with `:nbpr_cannelloni`, which solves the same problem with
  its own protocol and its own peer on both ends. Reach for this one when
  the far end is already running socketcand.

  ## Versioning

  **This package's Hex version is nbpr's own, not Buildroot's.** Buildroot
  pins a git-describe snapshot (`0.6.1-103-g6dd5d33…`) that hex.pm can't
  hold — it parses as a pre-release, which no `~>` requirement ever
  resolves. The upstream literal is declared as `upstream_version:` below,
  where the artefact cache key picks it up, so a Buildroot bump still
  invalidates prebuilt artefacts even though the Hex version didn't move.
  `mix nbpr.inspect NBPR.Socketcand` prints both.

  The practical consequence: `0.1.0` here says nothing about which
  socketcand you get. Read `upstream_version:` for that. The reasoning is
  in `docs/reference/versioning.md` in the nbpr repository, under
  "Decoupling".

  ## It does not fork

  socketcand's `-d`/`--daemon` flag is **not** in the option schema, and it
  wouldn't do what the name suggests anyway: it only redirects logging to
  syslog. The process stays in the foreground either way, which is what
  MuonTrap needs — and leaving it off keeps the log lines on stdout, where
  MuonTrap captures them into the BEAM's logger.

  The per-client `fork()`s are a different thing and are fine: the parent
  socket keeps listening, so the pid MuonTrap holds is the one that matters.

  ## The discovery beacon

  socketcand broadcasts a UDP beacon advertising itself and its buses, so
  clients can find it without being told an address. It goes out on
  `listen_interface`, which upstream defaults to `eth0` — rarely right on a
  Nerves device, so set it. `no_beacon: true` turns the broadcast off
  entirely when clients are configured with an address anyway.

  ## Bitrate control, and `libsocketcan`

  With the `libsocketcan` build option on (the default), socketcand can
  serve the protocol's interface-configuration commands — bitrate,
  controller mode, bus restarts — rather than refusing them. That's the
  difference between a remote client being able to *use* a bus and being
  able to *set it up*, so it's on unless you ask otherwise, and the package
  depends on `:nbpr_libsocketcan` to make sure the `.so` is in the firmware.

  Buildroot's `libconfig` option (socketcand reading a config file) is not
  exposed: it would need an `:nbpr_libconfig` package to turn on, and
  everything in that file is reachable through this module's options.

  ## Kernel requirements

  socketcand opens raw CAN sockets, so it needs `CONFIG_CAN` and
  `CONFIG_CAN_RAW` plus a driver — none of which stock Nerves systems
  enable. `NBPR.CanUtils`'s moduledoc has the full list. The configuration
  commands additionally want `CONFIG_CAN_DEV`.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "socketcand",
    upstream_version: "0.6.1-103-g6dd5d33d4645ab221e8cd265c08607366e21ddf1",
    description: "Daemon providing access to CAN interfaces over TCP",
    homepage: "https://github.com/linux-can/socketcand",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}],
    build_opts: [
      libsocketcan: [
        type: :boolean,
        default: true,
        br_flag: "BR2_PACKAGE_LIBSOCKETCAN",
        doc:
          "Serve the protocol's interface-configuration commands (bitrate, controller mode, bus restart) rather than refusing them. On by default; a remote client that can't configure a bus can only use one somebody else set up. Needs `:nbpr_libsocketcan` in the firmware, which this package depends on."
      ]
    ],
    daemons: [
      socketcand: [
        path: "/usr/sbin/socketcand",
        argv_template: {__MODULE__, :argv, []},
        opts: [
          interfaces: [
            type: {:list, :string},
            required: true,
            doc:
              "CAN interfaces to serve, e.g. `[\"can0\", \"can1\"]`. Passed to socketcand as a comma-separated list. Required: upstream's default is `vcan0`, which on a device is almost certainly not what you meant."
          ],
          listen_interface: [
            type: :string,
            flag: "-l",
            doc:
              "Network interface to bind and to broadcast the discovery beacon on. Unset leaves socketcand's default of `eth0`, which is rarely a Nerves device's name for anything."
          ],
          port: [
            type: :pos_integer,
            flag: "-p",
            doc: "TCP port to listen on. Unset leaves socketcand's default of 29536."
          ],
          afuxname: [
            type: :string,
            flag: "-u",
            doc:
              "Serve on an `AF_UNIX` socket at this path instead of TCP — an abstract name when there's no leading `/`. **Supersedes `port` and `listen_interface`**, so the daemon stops being reachable over the network at all. Put a filesystem path on the writable `/run` tmpfs."
          ],
          error_mask: [
            type: :string,
            flag: "-e",
            doc:
              "Deliver CAN error frames to clients in raw mode, as a hexadecimal mask, e.g. `\"0x1FFFFFFF\"` for all of them. Unset means no error frames."
          ],
          quick_ack: [
            type: :boolean,
            default: false,
            flag: "-q",
            doc:
              "Set `TCP_QUICKACK` on client sockets, trading ack traffic for latency on a busy bus."
          ],
          no_beacon: [
            type: :boolean,
            default: false,
            flag: "-n",
            doc:
              "Stop broadcasting the UDP discovery beacon. Worth setting when clients are configured with an address anyway, or when the device shouldn't announce its buses to the network."
          ],
          verbose: [
            type: :boolean,
            default: false,
            flag: "-v",
            doc: "Verbose output on stdout, which MuonTrap captures into the BEAM logs."
          ]
        ]
      ],
      socketcandcl: [
        path: "/usr/bin/socketcandcl",
        argv_template: {__MODULE__, :client_argv, []},
        opts: [
          server: [
            type: :string,
            required: true,
            flag: "-s",
            doc: "Hostname or address of the machine running socketcand."
          ],
          remote_interface: [
            type: :string,
            required: true,
            doc: "Bus to subscribe to on the server, e.g. `\"can0\"`."
          ],
          local_interface: [
            type: :string,
            required: true,
            doc:
              "Local interface to mirror the remote bus onto, e.g. `\"vcan0\"`. Needs `CONFIG_CAN_VCAN` if it's a virtual one."
          ],
          port: [
            type: :pos_integer,
            flag: "-p",
            doc: "Port to connect to. Unset leaves socketcandcl's default of 29536."
          ],
          afuxname: [
            type: :string,
            flag: "-u",
            doc:
              "Connect to an `AF_UNIX` socket at this path instead of TCP — an abstract name when there's no leading `/`."
          ],
          verbose: [
            type: :boolean,
            default: false,
            flag: "-v",
            doc: "Verbose output on stdout, which MuonTrap captures into the BEAM logs."
          ]
        ]
      ]
    ]

  @doc """
  Builds socketcand's argv, joining `:interfaces` into the comma-separated
  form `-i` expects.

  socketcand takes one `-i` with a comma-separated value rather than a
  repeated flag, which `NBPR.BrPackage.default_argv/2` can't express — so
  this pops `:interfaces` off, delegates the flagged options, and prepends
  the joined list.
  """
  @spec argv(keyword(), %{atom() => String.t()}) :: [String.t()]
  def argv(opts, opt_flags) do
    {interfaces, flagged} = Keyword.pop!(opts, :interfaces)

    ["-i", Enum.join(interfaces, ",")] ++ NBPR.BrPackage.default_argv(flagged, opt_flags)
  end

  @doc """
  Builds socketcandcl's argv, pairing the remote and local interfaces into
  the single `-i <remote>,<local>` argument it parses.

  Upstream splits that one option on the comma and assigns the halves in
  order, so the pair is positional inside the value. Naming them separately
  here keeps the caller from having to know that.
  """
  @spec client_argv(keyword(), %{atom() => String.t()}) :: [String.t()]
  def client_argv(opts, opt_flags) do
    {remote, opts} = Keyword.pop!(opts, :remote_interface)
    {local, flagged} = Keyword.pop!(opts, :local_interface)

    ["-i", "#{remote},#{local}"] ++ NBPR.BrPackage.default_argv(flagged, opt_flags)
  end
end
