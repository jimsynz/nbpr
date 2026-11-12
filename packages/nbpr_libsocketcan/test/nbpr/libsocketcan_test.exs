defmodule NBPR.LibsocketcanTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Libsocketcan.__nbpr_package__()

      assert pkg.module == NBPR.Libsocketcan
      assert pkg.name == :libsocketcan
      assert pkg.version == 1
      assert pkg.br_package == "libsocketcan"
      assert pkg.description == "C library for configuring SocketCAN interfaces over netlink"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.build_opts == []
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end
  end
end
