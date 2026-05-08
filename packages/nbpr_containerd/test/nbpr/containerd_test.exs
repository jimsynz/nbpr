defmodule NBPR.ContainerdTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "has the expected shape" do
      pkg = NBPR.Containerd.__nbpr_package__()

      assert pkg.module == NBPR.Containerd
      assert pkg.name == :containerd
      assert pkg.version == 1
      assert pkg.br_package == "containerd"
      assert pkg.homepage == "https://containerd.io/"
      assert pkg.artifact_sites == [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
      assert pkg.kernel_modules == []

      [daemon] = pkg.daemons
      assert daemon.name == :containerd
      assert daemon.module == NBPR.Containerd.Containerd
      assert daemon.path == "/usr/bin/containerd"

      assert daemon.opt_flags == %{
               config: "--config",
               root: "--root",
               state: "--state",
               address: "--address",
               log_level: "--log-level"
             }
    end
  end

  describe "generated daemon module" do
    test "exports child_spec/1, start_link/1, argv/1, binary_path/0" do
      assert Code.ensure_loaded?(NBPR.Containerd.Containerd)
      assert function_exported?(NBPR.Containerd.Containerd, :child_spec, 1)
      assert function_exported?(NBPR.Containerd.Containerd, :start_link, 1)
      assert function_exported?(NBPR.Containerd.Containerd, :argv, 1)
      assert function_exported?(NBPR.Containerd.Containerd, :binary_path, 0)
    end

    test "binary_path/0 resolves under the package's priv dir" do
      path = NBPR.Containerd.Containerd.binary_path()
      assert path =~ "lib/nbpr_containerd"
      assert String.ends_with?(path, "usr/bin/containerd")
    end

    test "argv emits flag/value pairs only for opts that are set" do
      assert NBPR.Containerd.Containerd.argv(config: "/etc/containerd/config.toml") ==
               ["--config", "/etc/containerd/config.toml"]
    end

    test "argv emits all set opts in schema order" do
      argv =
        NBPR.Containerd.Containerd.argv(
          config: "/etc/containerd/config.toml",
          root: "/data/containerd",
          state: "/run/containerd",
          address: "/run/containerd/containerd.sock",
          log_level: "info"
        )

      assert argv == [
               "--config",
               "/etc/containerd/config.toml",
               "--root",
               "/data/containerd",
               "--state",
               "/run/containerd",
               "--address",
               "/run/containerd/containerd.sock",
               "--log-level",
               "info"
             ]
    end

    test "argv with no opts is empty (containerd uses internal defaults)" do
      assert NBPR.Containerd.Containerd.argv([]) == []
    end
  end
end
