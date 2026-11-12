defmodule NBPR.CannelloniTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Cannelloni.__nbpr_package__()

      assert pkg.module == NBPR.Cannelloni
      assert pkg.name == :cannelloni
      assert pkg.version == 1
      assert pkg.br_package == "cannelloni"
      assert pkg.description == "SocketCAN over Ethernet tunnel"
      assert pkg.homepage == "https://github.com/mguentner/cannelloni"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.build_opts == []
      assert pkg.kernel_modules == []

      [daemon] = pkg.daemons
      assert daemon.name == :cannelloni
      assert daemon.module == NBPR.Cannelloni.Cannelloni
      assert daemon.path == "/usr/bin/cannelloni"
    end
  end

  describe "generated daemon module" do
    test "exports child_spec/1, start_link/1, argv/1, binary_path/0" do
      assert Code.ensure_loaded?(NBPR.Cannelloni.Cannelloni)
      assert function_exported?(NBPR.Cannelloni.Cannelloni, :child_spec, 1)
      assert function_exported?(NBPR.Cannelloni.Cannelloni, :start_link, 1)
      assert function_exported?(NBPR.Cannelloni.Cannelloni, :argv, 1)
      assert function_exported?(NBPR.Cannelloni.Cannelloni, :binary_path, 0)
    end

    test "binary_path/0 resolves under the package's priv dir" do
      path = NBPR.Cannelloni.Cannelloni.binary_path()

      assert path =~ "lib/nbpr_cannelloni"
      assert String.ends_with?(path, "usr/bin/cannelloni")
    end
  end

  describe "argv/1" do
    # A tunnel with no interface has nothing to tunnel, and cannelloni's own
    # default of `vcan0` would quietly attach to the wrong thing.
    test "raises when no CAN interface is named" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NBPR.Cannelloni.Cannelloni.argv(remote_address: "10.0.0.2")
      end
    end

    test "names the interface and peer it was given" do
      argv = NBPR.Cannelloni.Cannelloni.argv(can_interface: "can0", remote_address: "10.0.0.2")

      assert ["-I", "can0"] == Enum.slice(argv, Enum.find_index(argv, &(&1 == "-I")), 2)
      assert ["-R", "10.0.0.2"] == Enum.slice(argv, Enum.find_index(argv, &(&1 == "-R")), 2)
    end

    # UDP is the absence of `-C`, not a value for it, so the default has to
    # emit nothing rather than `-C udp`.
    test "emits no transport flag for the default UDP transport" do
      argv = NBPR.Cannelloni.Cannelloni.argv(can_interface: "can0", remote_address: "10.0.0.2")

      refute "-C" in argv
      refute "udp" in argv
    end

    # Added in cannelloni 2.1.x; without it a peer outage queues frames and
    # then floods the bus with stale ones when the link returns.
    test "passes the stale-frame drop timeout" do
      argv =
        NBPR.Cannelloni.Cannelloni.argv(
          can_interface: "can0",
          remote_address: "10.0.0.2",
          stale_timeout_us: 500_000
        )

      assert "-x" in argv and "500000" in argv
    end

    test "maps the TCP roles onto cannelloni's single-letter argument" do
      client = NBPR.Cannelloni.Cannelloni.argv(can_interface: "can0", transport: :tcp_client)
      server = NBPR.Cannelloni.Cannelloni.argv(can_interface: "can0", transport: :tcp_server)

      assert ["-C", "c"] == Enum.take(client, 2)
      assert ["-C", "s"] == Enum.take(server, 2)
    end

    test "leaves unset options to cannelloni's own defaults" do
      argv = NBPR.Cannelloni.Cannelloni.argv(can_interface: "can0", remote_address: "10.0.0.2")

      refute "-l" in argv
      refute "-r" in argv
      refute "-t" in argv
      refute "-m" in argv
      refute "-x" in argv
    end

    # Forking would hand MuonTrap a pid that exits immediately, so neither
    # flag is in the schema to be passed.
    test "has no way to ask for daemon mode" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NBPR.Cannelloni.Cannelloni.argv(can_interface: "can0", fork: true)
      end
    end
  end
end
