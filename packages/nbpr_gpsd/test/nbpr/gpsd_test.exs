defmodule NBPR.GpsdTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Gpsd.__nbpr_package__()

      assert pkg.module == NBPR.Gpsd
      assert pkg.name == :gpsd
      assert pkg.version == 1
      assert pkg.br_package == "gpsd"
      assert pkg.homepage == "https://gpsd.gitlab.io/gpsd"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.kernel_modules == []

      [daemon] = pkg.daemons
      assert daemon.name == :gpsd
      assert daemon.module == NBPR.Gpsd.Gpsd
      assert daemon.path == "/usr/sbin/gpsd"
      assert daemon.argv_template == {NBPR.Gpsd, :argv, []}
    end

    test "devices has no flag mapping, since it's positional" do
      [daemon] = NBPR.Gpsd.__nbpr_package__().daemons

      assert daemon.opt_flags[:devices] == nil
      assert daemon.opt_flags[:foreground] == "-N"
      assert daemon.opt_flags[:sockfile] == "-F"
    end
  end

  describe "build options" do
    test "every one maps to a Buildroot flag" do
      pkg = NBPR.Gpsd.__nbpr_package__()

      for {name, _spec} <- pkg.build_opts do
        assert %{br_flag: "BR2_" <> _} = pkg.build_opt_extensions[name],
               "#{name} has no :br_flag"
      end
    end

    test "covers all 22 protocol drivers Buildroot exposes" do
      gpsd_flags =
        NBPR.Gpsd.__nbpr_package__().build_opt_extensions
        |> Map.values()
        |> Enum.map(& &1.br_flag)
        |> Enum.filter(&String.starts_with?(&1, "BR2_PACKAGE_GPSD_"))

      # The 22 drivers plus CLIENTS, CLIENT_DEBUG and SQUELCH.
      assert length(gpsd_flags) == 25
      assert "BR2_PACKAGE_GPSD_TRIMBLE_TSIP" in gpsd_flags
      assert "BR2_PACKAGE_GPSD_AIVDM" in gpsd_flags
      assert "BR2_PACKAGE_GPSD_NMEA2000" in gpsd_flags
    end

    test "ncurses and pps set sibling packages' Buildroot flags" do
      extensions = NBPR.Gpsd.__nbpr_package__().build_opt_extensions

      assert extensions[:ncurses].br_flag == "BR2_PACKAGE_NCURSES"
      assert extensions[:pps].br_flag == "BR2_PACKAGE_PPS_TOOLS"
    end

    test "only the client tools are on by default" do
      pkg = NBPR.Gpsd.__nbpr_package__()
      validated = NimbleOptions.validate!([], NimbleOptions.new!(pkg.build_opts))
      {enabled, disabled} = Enum.split_with(validated, fn {_name, value} -> value end)

      assert Keyword.keys(enabled) == [:clients]
      assert length(disabled) == 26
    end
  end

  describe "generated daemon module" do
    test "exports child_spec/1, start_link/1, argv/1, binary_path/0" do
      assert Code.ensure_loaded?(NBPR.Gpsd.Gpsd)
      assert function_exported?(NBPR.Gpsd.Gpsd, :child_spec, 1)
      assert function_exported?(NBPR.Gpsd.Gpsd, :start_link, 1)
      assert function_exported?(NBPR.Gpsd.Gpsd, :argv, 1)
      assert function_exported?(NBPR.Gpsd.Gpsd, :binary_path, 0)
    end

    test "binary_path/0 resolves under the package's priv dir" do
      path = NBPR.Gpsd.Gpsd.binary_path()

      assert path =~ "lib/nbpr_gpsd"
      assert String.ends_with?(path, "usr/sbin/gpsd")
    end

    test "child_spec returns a supervisor child spec map" do
      spec = NBPR.Gpsd.Gpsd.child_spec(devices: ["/dev/ttyAMA0"])

      assert spec.id == NBPR.Gpsd.Gpsd
      assert {NBPR.Gpsd.Gpsd, :start_link, [_]} = spec.start
    end
  end

  describe "argv/1" do
    test "appends devices as positional arguments after the flags" do
      assert NBPR.Gpsd.Gpsd.argv(devices: ["/dev/ttyAMA0"]) ==
               ["-N", "-n", "-S", "2947", "/dev/ttyAMA0"]
    end

    test "preserves device order" do
      argv = NBPR.Gpsd.Gpsd.argv(devices: ["/dev/ttyAMA0", "tcp://rtk.example:2101"])

      assert Enum.take(argv, -2) == ["/dev/ttyAMA0", "tcp://rtk.example:2101"]
    end

    test "accepts an empty device list, for control-socket-driven setups" do
      assert NBPR.Gpsd.Gpsd.argv(devices: [], sockfile: "/run/gpsd.sock") ==
               ["-N", "-n", "-S", "2947", "-F", "/run/gpsd.sock"]
    end

    test "emits value-bearing flags and omits unset ones" do
      argv = NBPR.Gpsd.Gpsd.argv(devices: ["/dev/ttyUSB0"], debug: 2, speed: 115_200)

      assert ["-D", "2"] == argv |> Enum.drop_while(&(&1 != "-D")) |> Enum.take(2)
      assert ["-s", "115200"] == argv |> Enum.drop_while(&(&1 != "-s")) |> Enum.take(2)
      refute "-f" in argv
      refute "-F" in argv
    end

    test "omits boolean flags when false" do
      argv = NBPR.Gpsd.Gpsd.argv(devices: ["/dev/ttyAMA0"], nowait: false)

      refute "-n" in argv
      assert "-N" in argv
    end

    test "raises when devices is missing" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NBPR.Gpsd.Gpsd.argv([])
      end
    end

    test "raises when devices is not a list of strings" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NBPR.Gpsd.Gpsd.argv(devices: "/dev/ttyAMA0")
      end
    end
  end
end
