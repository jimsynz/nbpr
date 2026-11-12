defmodule NBPR.SocketcandTest do
  use ExUnit.Case, async: true

  @upstream "0.6.1-103-g6dd5d33d4645ab221e8cd265c08607366e21ddf1"

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Socketcand.__nbpr_package__()

      assert pkg.module == NBPR.Socketcand
      assert pkg.name == :socketcand
      assert pkg.version == 1
      assert pkg.br_package == "socketcand"
      assert pkg.description == "Daemon providing access to CAN interfaces over TCP"
      assert pkg.homepage == "https://github.com/linux-can/socketcand"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.kernel_modules == []

      [server, client] = pkg.daemons

      assert server.name == :socketcand
      assert server.module == NBPR.Socketcand.Socketcand
      # Upstream's meson installs the daemon to sbindir and the client to
      # bindir; NBPR.Application puts both on PATH.
      assert server.path == "/usr/sbin/socketcand"

      assert client.name == :socketcandcl
      assert client.module == NBPR.Socketcand.Socketcandcl
      assert client.path == "/usr/bin/socketcandcl"
    end
  end

  describe "decoupled version" do
    # Buildroot pins a git-describe snapshot that hex.pm won't take, so this
    # package's Hex version is nbpr's own and the upstream one lives here.
    test "declares Buildroot's literal" do
      pkg = NBPR.Socketcand.__nbpr_package__()

      assert pkg.upstream_version == @upstream
    end

    test "the Hex version is one hex.pm accepts and the upstream one is not" do
      hex_version = to_string(Application.spec(:nbpr_socketcand, :vsn))

      assert NBPR.Version.validate(hex_version) == :ok
      assert {:error, _} = NBPR.Version.validate(NBPR.Version.hex_version(@upstream))
    end

    # Without this the cache key would sit still across a Buildroot bump and
    # a stale artefact would be served for new sources.
    test "the upstream version reaches the artefact cache key" do
      pkg = NBPR.Socketcand.__nbpr_package__()

      inputs = %{
        package_name: "nbpr_socketcand",
        package_version: "0.1.0",
        system_app: :nerves_system_rpi4,
        system_version: "2.1.2",
        build_opts: [libsocketcan: true]
      }

      with_upstream = Map.put(inputs, :upstream_version, pkg.upstream_version)
      bumped = Map.put(inputs, :upstream_version, "0.6.1-117-gbadf00d")

      assert NBPR.Artifact.cache_key(with_upstream) != NBPR.Artifact.cache_key(inputs)
      assert NBPR.Artifact.cache_key(with_upstream) != NBPR.Artifact.cache_key(bumped)
    end
  end

  describe "build options" do
    test "libsocketcan is on by default" do
      pkg = NBPR.Socketcand.__nbpr_package__()

      assert pkg.build_opts[:libsocketcan][:default] == true

      assert pkg.build_opt_extensions[:libsocketcan][:br_flag] == "BR2_PACKAGE_LIBSOCKETCAN"
    end
  end

  describe "generated daemon module" do
    test "exports child_spec/1, start_link/1, argv/1, binary_path/0" do
      assert Code.ensure_loaded?(NBPR.Socketcand.Socketcand)
      assert function_exported?(NBPR.Socketcand.Socketcand, :child_spec, 1)
      assert function_exported?(NBPR.Socketcand.Socketcand, :start_link, 1)
      assert function_exported?(NBPR.Socketcand.Socketcand, :argv, 1)
      assert function_exported?(NBPR.Socketcand.Socketcand, :binary_path, 0)
    end

    test "binary_path/0 resolves under the package's priv dir" do
      path = NBPR.Socketcand.Socketcand.binary_path()

      assert path =~ "lib/nbpr_socketcand"
      assert String.ends_with?(path, "usr/sbin/socketcand")
    end
  end

  describe "argv/1" do
    # Upstream defaults to `vcan0`, which would quietly serve the wrong bus.
    test "raises when no interface is named" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NBPR.Socketcand.Socketcand.argv([])
      end
    end

    # socketcand takes one `-i` with a comma-separated value, not a repeated
    # flag, so the list has to be joined rather than expanded.
    test "joins interfaces into socketcand's comma-separated form" do
      assert ["-i", "can0,can1" | _] =
               NBPR.Socketcand.Socketcand.argv(interfaces: ["can0", "can1"])
    end

    test "passes a single interface through unjoined" do
      assert ["-i", "can0" | _] = NBPR.Socketcand.Socketcand.argv(interfaces: ["can0"])
    end

    test "names the listen interface and port it was given" do
      argv =
        NBPR.Socketcand.Socketcand.argv(
          interfaces: ["can0"],
          listen_interface: "wlan0",
          port: 30000
        )

      assert "-l" in argv and "wlan0" in argv
      assert "-p" in argv and "30000" in argv
    end

    test "leaves unset options to socketcand's own defaults" do
      argv = NBPR.Socketcand.Socketcand.argv(interfaces: ["can0"])

      refute "-p" in argv
      refute "-l" in argv
      refute "-u" in argv
      refute "-e" in argv
    end

    # `-d` only redirects logging to syslog, which would hide the daemon's
    # output from MuonTrap, so it isn't in the schema to be passed.
    test "has no way to ask for syslog logging" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NBPR.Socketcand.Socketcand.argv(interfaces: ["can0"], daemon: true)
      end
    end
  end

  describe "client_argv/1" do
    test "exports the same daemon surface as the server" do
      assert Code.ensure_loaded?(NBPR.Socketcand.Socketcandcl)
      assert function_exported?(NBPR.Socketcand.Socketcandcl, :child_spec, 1)
      assert function_exported?(NBPR.Socketcand.Socketcandcl, :argv, 1)

      assert String.ends_with?(
               NBPR.Socketcand.Socketcandcl.binary_path(),
               "usr/bin/socketcandcl"
             )
    end

    # Upstream splits one `-i` value on the comma and assigns remote then
    # local, in that order — getting it backwards would mirror the wrong way.
    test "pairs the remote and local interfaces in upstream's order" do
      argv =
        NBPR.Socketcand.Socketcandcl.argv(
          server: "10.0.0.2",
          remote_interface: "can0",
          local_interface: "vcan0"
        )

      assert ["-i", "can0,vcan0" | _] = argv
      assert "-s" in argv and "10.0.0.2" in argv
    end

    test "requires the server and both interfaces" do
      for opts <- [
            [remote_interface: "can0", local_interface: "vcan0"],
            [server: "10.0.0.2", local_interface: "vcan0"],
            [server: "10.0.0.2", remote_interface: "can0"]
          ] do
        assert_raise NimbleOptions.ValidationError, fn ->
          NBPR.Socketcand.Socketcandcl.argv(opts)
        end
      end
    end
  end
end
