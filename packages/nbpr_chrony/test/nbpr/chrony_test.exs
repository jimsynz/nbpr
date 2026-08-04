defmodule NBPR.ChronyTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Chrony.__nbpr_package__()

      assert pkg.module == NBPR.Chrony
      assert pkg.name == :chrony
      assert pkg.version == 1
      assert pkg.br_package == "chrony"
      assert pkg.homepage == "https://chrony-project.org/"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.kernel_modules == []

      [daemon] = pkg.daemons
      assert daemon.name == :chronyd
      assert daemon.module == NBPR.Chrony.Chronyd
      assert daemon.path == "/usr/sbin/chronyd"
    end

    test "debug_logging maps to its Buildroot flag" do
      pkg = NBPR.Chrony.__nbpr_package__()

      assert Keyword.keys(pkg.build_opts) == [:debug_logging]

      assert pkg.build_opt_extensions[:debug_logging].br_flag ==
               "BR2_PACKAGE_CHRONY_DEBUG_LOGGING"
    end
  end

  describe "generated daemon module" do
    test "exports child_spec/1, start_link/1, argv/1, binary_path/0" do
      assert Code.ensure_loaded?(NBPR.Chrony.Chronyd)
      assert function_exported?(NBPR.Chrony.Chronyd, :child_spec, 1)
      assert function_exported?(NBPR.Chrony.Chronyd, :start_link, 1)
      assert function_exported?(NBPR.Chrony.Chronyd, :argv, 1)
      assert function_exported?(NBPR.Chrony.Chronyd, :binary_path, 0)
    end

    test "binary_path/0 resolves under the package's priv dir" do
      path = NBPR.Chrony.Chronyd.binary_path()

      assert path =~ "lib/nbpr_chrony"
      assert String.ends_with?(path, "usr/sbin/chronyd")
    end
  end

  describe "argv/1" do
    test "runs in the foreground by default, for MuonTrap" do
      assert NBPR.Chrony.Chronyd.argv(config_file: "/etc/chrony.conf") ==
               ["-f", "/etc/chrony.conf", "-n"]
    end

    test "emits the clock-setting, memory-locking and priority flags" do
      argv =
        NBPR.Chrony.Chronyd.argv(
          config_file: "/etc/chrony.conf",
          set_clock_from_driftfile: true,
          lock_memory: true,
          priority: 50
        )

      assert argv == ["-f", "/etc/chrony.conf", "-n", "-s", "-m", "-P", "50"]
    end

    test "accepts a negative log level" do
      argv = NBPR.Chrony.Chronyd.argv(config_file: "/etc/chrony.conf", log_level: -1)

      assert ["-L", "-1"] == argv |> Enum.drop_while(&(&1 != "-L")) |> Enum.take(2)
    end

    test "raises when config_file is missing" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NBPR.Chrony.Chronyd.argv([])
      end
    end
  end
end
