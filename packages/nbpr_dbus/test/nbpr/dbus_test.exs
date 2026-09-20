defmodule NBPR.DbusTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Dbus.__nbpr_package__()

      assert pkg.module == NBPR.Dbus
      assert pkg.name == :dbus
      assert pkg.version == 1
      assert pkg.br_package == "dbus"
      assert pkg.description == "The D-Bus message bus system."
      assert pkg.homepage == "https://www.freedesktop.org/wiki/Software/dbus"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.kernel_modules == []

      [daemon] = pkg.daemons
      assert daemon.name == :dbus_daemon
      assert daemon.module == NBPR.Dbus.DbusDaemon
      assert daemon.path == "/usr/bin/dbus-daemon"
    end
  end

  describe "generated daemon module" do
    test "exports child_spec/1, start_link/1, argv/1, binary_path/0" do
      assert Code.ensure_loaded?(NBPR.Dbus.DbusDaemon)
      assert function_exported?(NBPR.Dbus.DbusDaemon, :child_spec, 1)
      assert function_exported?(NBPR.Dbus.DbusDaemon, :start_link, 1)
      assert function_exported?(NBPR.Dbus.DbusDaemon, :argv, 1)
      assert function_exported?(NBPR.Dbus.DbusDaemon, :binary_path, 0)
    end

    test "binary_path/0 resolves under the package's priv dir" do
      path = NBPR.Dbus.DbusDaemon.binary_path()

      assert path =~ "lib/nbpr_dbus"
      assert String.ends_with?(path, "usr/bin/dbus-daemon")
    end
  end

  describe "argv/1" do
    # A daemon that forks is one MuonTrap loses.
    test "stays in the foreground by default" do
      assert NBPR.Dbus.DbusDaemon.argv(config_file: "/etc/dbus-1/system.conf") ==
               ["--config-file", "/etc/dbus-1/system.conf", "--nofork"]
    end

    test "emits the address and syslog flags" do
      argv =
        NBPR.Dbus.DbusDaemon.argv(
          config_file: "/etc/dbus-1/system.conf",
          print_address: true,
          syslog: true
        )

      assert "--print-address" in argv
      assert "--syslog" in argv
    end

    # The compiled-in default path does not exist on a Nerves rootfs, so a caller
    # that named none would get a daemon that will not start.
    test "raises when config_file is missing" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NBPR.Dbus.DbusDaemon.argv([])
      end
    end
  end
end
