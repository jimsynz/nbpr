defmodule NBPR.Bluez5UtilsTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Bluez5Utils.__nbpr_package__()

      assert pkg.module == NBPR.Bluez5Utils
      assert pkg.name == :bluez5_utils
      assert pkg.version == 1
      assert pkg.br_package == "bluez5_utils"
      assert pkg.homepage == "http://www.bluez.org"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.kernel_modules == []

      [daemon] = pkg.daemons
      assert daemon.name == :bluetoothd
      assert daemon.module == NBPR.Bluez5Utils.Bluetoothd
      assert daemon.path == "/usr/libexec/bluetooth/bluetoothd"
    end

    # A2DP and AVRCP live in the audio plugins, and bluez-alsa is useless without
    # them, so this is the one build option that is on by default.
    test "the audio plugins are built by default" do
      pkg = NBPR.Bluez5Utils.__nbpr_package__()

      assert pkg.build_opts[:audio][:default] == true

      assert pkg.build_opt_extensions[:audio].br_flag ==
               "BR2_PACKAGE_BLUEZ5_UTILS_PLUGINS_AUDIO"
    end

    test "every other build option maps to a Buildroot flag and stays off" do
      pkg = NBPR.Bluez5Utils.__nbpr_package__()

      for key <- [:client, :tools, :monitor, :obex, :hid, :experimental] do
        assert pkg.build_opts[key][:default] == false
        assert pkg.build_opt_extensions[key].br_flag =~ "BR2_PACKAGE_BLUEZ5_UTILS"
      end
    end
  end

  describe "generated daemon module" do
    test "exports child_spec/1, start_link/1, argv/1, binary_path/0" do
      assert Code.ensure_loaded?(NBPR.Bluez5Utils.Bluetoothd)
      assert function_exported?(NBPR.Bluez5Utils.Bluetoothd, :child_spec, 1)
      assert function_exported?(NBPR.Bluez5Utils.Bluetoothd, :start_link, 1)
      assert function_exported?(NBPR.Bluez5Utils.Bluetoothd, :argv, 1)
      assert function_exported?(NBPR.Bluez5Utils.Bluetoothd, :binary_path, 0)
    end

    test "binary_path/0 resolves under the package's priv dir" do
      path = NBPR.Bluez5Utils.Bluetoothd.binary_path()

      assert path =~ "lib/nbpr_bluez5_utils"
      assert String.ends_with?(path, "usr/libexec/bluetooth/bluetoothd")
    end
  end

  describe "argv/1" do
    # A daemon that detaches is one MuonTrap loses.
    test "stays in the foreground by default, and needs nothing else" do
      assert NBPR.Bluez5Utils.Bluetoothd.argv([]) == ["--nodetach"]
    end

    test "names a plugin list and a config file when it is given them" do
      argv =
        NBPR.Bluez5Utils.Bluetoothd.argv(
          config_file: "/etc/bluetooth/main.conf",
          plugin: "a2dp,avrcp"
        )

      assert "--configfile" in argv
      assert "/etc/bluetooth/main.conf" in argv
      assert "a2dp,avrcp" in argv
    end
  end
end
