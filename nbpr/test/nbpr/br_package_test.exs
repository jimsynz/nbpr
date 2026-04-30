defmodule NBPR.BrPackageTest do
  use ExUnit.Case, async: true

  alias NBPR.Package
  alias NBPR.Package.Daemon

  defmodule TestDaemonless do
    use NBPR.BrPackage,
      version: 1,
      br_package: "jq",
      description: "test daemonless package",
      homepage: "https://example.test/",
      build_opts: [
        oniguruma: [
          type: :boolean,
          default: true,
          br_flag: "BR2_PACKAGE_JQ_ONIGURUMA",
          doc: "Enable Oniguruma regex support"
        ]
      ]
  end

  defmodule TestWithDaemon do
    use NBPR.BrPackage,
      version: 1,
      br_package: "dnsmasq",
      description: "test daemon-bearing package",
      daemons: [
        myd: [
          path: "/usr/sbin/myd",
          opts: [
            config_file: [type: :string, required: true, flag: "--conf-file", doc: "Config path"],
            verbose: [type: :boolean, default: false, flag: "--verbose", doc: "Verbose mode"],
            mode: [type: :string, default: "normal", flag: "--mode", doc: "Mode"]
          ]
        ]
      ]
  end

  defmodule CustomArgv do
    def build([config_file: path], _flags), do: ["serve", "--from", path]
  end

  defmodule TestWithCustomArgv do
    use NBPR.BrPackage,
      version: 1,
      br_package: "custom",
      description: "test argv override",
      daemons: [
        custom: [
          path: "/usr/bin/custom",
          opts: [
            config_file: [type: :string, required: true]
          ],
          argv_template: {NBPR.BrPackageTest.CustomArgv, :build, []}
        ]
      ]
  end

  defmodule TestWithKmods do
    use NBPR.BrPackage,
      version: 1,
      br_package: "zfs",
      description: "test kernel-module-bearing package",
      kernel_modules: ["spl", "zfs"]
  end

  describe "__nbpr_package__/0 — daemonless" do
    test "returns metadata struct with the expected fields" do
      pkg = TestDaemonless.__nbpr_package__()

      assert %Package{} = pkg
      assert pkg.name == :test_daemonless
      assert pkg.version == 1
      assert pkg.module == TestDaemonless
      assert pkg.description == "test daemonless package"
      assert pkg.homepage == "https://example.test/"
      assert pkg.br_package == "jq"
      assert pkg.br_external_path == nil
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end

    test "splits :br_flag out of build_opts into build_opt_extensions" do
      pkg = TestDaemonless.__nbpr_package__()

      assert %{br_flag: "BR2_PACKAGE_JQ_ONIGURUMA"} = pkg.build_opt_extensions[:oniguruma]

      assert Keyword.fetch!(pkg.build_opts, :oniguruma) ==
               [type: :boolean, default: true, doc: "Enable Oniguruma regex support"]
    end
  end

  describe "__nbpr_package__/0 — daemon-bearing" do
    test "exposes daemon metadata" do
      pkg = TestWithDaemon.__nbpr_package__()

      assert [%Daemon{} = daemon] = pkg.daemons
      assert daemon.name == :myd
      assert daemon.path == "/usr/sbin/myd"
      assert daemon.module == TestWithDaemon.Myd

      assert daemon.opt_flags == %{
               config_file: "--conf-file",
               verbose: "--verbose",
               mode: "--mode"
             }

      assert daemon.argv_template == {NBPR.BrPackage, :default_argv, []}
    end
  end

  describe "generated daemon module" do
    test "exports child_spec/1, start_link/1, argv/1" do
      assert function_exported?(TestWithDaemon.Myd, :child_spec, 1)
      assert function_exported?(TestWithDaemon.Myd, :start_link, 1)
      assert function_exported?(TestWithDaemon.Myd, :argv, 1)
    end

    test "child_spec/1 returns a supervisor child spec map" do
      spec = TestWithDaemon.Myd.child_spec(config_file: "/etc/m.conf")
      assert spec.id == TestWithDaemon.Myd
      assert {TestWithDaemon.Myd, :start_link, [_]} = spec.start
    end
  end

  describe "default argv assembly" do
    test "fills defaults and emits flag/value pairs" do
      assert TestWithDaemon.Myd.argv(config_file: "/etc/m.conf") ==
               ["--conf-file", "/etc/m.conf", "--mode", "normal"]
    end

    test "omits boolean opts when false" do
      argv = TestWithDaemon.Myd.argv(config_file: "/etc/m.conf", verbose: false)
      refute "--verbose" in argv
    end

    test "emits flag-only when boolean is true" do
      argv = TestWithDaemon.Myd.argv(config_file: "/etc/m.conf", verbose: true)
      verbose_index = Enum.find_index(argv, &(&1 == "--verbose"))
      assert verbose_index
      assert Enum.at(argv, verbose_index + 1, "--mode") in ["--mode", nil]
    end

    test "raises NimbleOptions error when required opt is missing" do
      assert_raise NimbleOptions.ValidationError, fn ->
        TestWithDaemon.Myd.argv([])
      end
    end
  end

  describe "argv_template override via MFA" do
    test "calls the user-supplied function instead of default_argv" do
      assert TestWithCustomArgv.Custom.argv(config_file: "/srv/cfg") ==
               ["serve", "--from", "/srv/cfg"]
    end
  end

  describe "kernel-module Application generation" do
    test "Application module is generated when kernel_modules is non-empty" do
      assert Code.ensure_loaded?(TestWithKmods.Application)
      assert function_exported?(TestWithKmods.Application, :start, 2)
      assert function_exported?(TestWithKmods.Application, :stop, 1)
      assert function_exported?(TestWithKmods.Application, :kernel_modules, 0)
    end

    test "Application module is NOT generated when kernel_modules is empty" do
      refute Code.ensure_loaded?(TestDaemonless.Application)
    end

    test "kernel_modules/0 returns the declared list" do
      assert TestWithKmods.Application.kernel_modules() == ["spl", "zfs"]
    end

    test "start/2 succeeds on dev host (modprobe gated off)" do
      assert {:ok, pid} = TestWithKmods.Application.start(:normal, [])
      assert is_pid(pid)
      assert Process.alive?(pid)

      assert TestWithKmods.Application.stop(nil) == :ok
      Supervisor.stop(pid)
    end
  end

  describe "compile-time validations" do
    test "rejects both :br_package and :br_external_path" do
      assert_raise ArgumentError, ~r/mutually exclusive/, fn ->
        Code.eval_string("""
        defmodule NBPR.BrPackageTest.Both do
          use NBPR.BrPackage,
            version: 1,
            br_package: "x",
            br_external_path: "/y",
            description: "x"
        end
        """)
      end
    end

    test "rejects neither :br_package nor :br_external_path" do
      assert_raise ArgumentError, ~r/must specify exactly one/, fn ->
        Code.eval_string("""
        defmodule NBPR.BrPackageTest.Neither do
          use NBPR.BrPackage,
            version: 1,
            description: "x"
        end
        """)
      end
    end

    test "rejects unsupported version" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Code.eval_string("""
        defmodule NBPR.BrPackageTest.BadVersion do
          use NBPR.BrPackage,
            version: 99,
            br_package: "x",
            description: "x"
        end
        """)
      end
    end

    test "rejects missing :description" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Code.eval_string("""
        defmodule NBPR.BrPackageTest.NoDescription do
          use NBPR.BrPackage,
            version: 1,
            br_package: "x"
        end
        """)
      end
    end
  end
end
