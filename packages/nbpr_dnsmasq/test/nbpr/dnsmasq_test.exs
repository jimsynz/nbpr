defmodule NBPR.DnsmasqTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "has the expected shape" do
      pkg = NBPR.Dnsmasq.__nbpr_package__()

      assert pkg.module == NBPR.Dnsmasq
      assert pkg.name == :dnsmasq
      assert pkg.br_package == "dnsmasq"
      assert pkg.artifact_sites == [{:ghcr, "ghcr.io/jimsynz"}]

      [daemon] = pkg.daemons
      assert daemon.name == :dnsmasq
      assert daemon.module == NBPR.Dnsmasq.Dnsmasq
      assert daemon.path == "/usr/sbin/dnsmasq"

      assert daemon.opt_flags == %{
               config_file: "--conf-file",
               keep_in_foreground: "--keep-in-foreground",
               pid_file: "--pid-file",
               log_facility: "--log-facility"
             }
    end
  end

  describe "generated daemon module" do
    test "exports child_spec/1, start_link/1, argv/1" do
      assert function_exported?(NBPR.Dnsmasq.Dnsmasq, :child_spec, 1)
      assert function_exported?(NBPR.Dnsmasq.Dnsmasq, :start_link, 1)
      assert function_exported?(NBPR.Dnsmasq.Dnsmasq, :argv, 1)
    end

    test "child_spec returns a supervisor child spec map" do
      spec = NBPR.Dnsmasq.Dnsmasq.child_spec(config_file: "/etc/dnsmasq.conf")
      assert spec.id == NBPR.Dnsmasq.Dnsmasq
      assert {NBPR.Dnsmasq.Dnsmasq, :start_link, [_]} = spec.start
    end

    test "argv fills defaults and emits flag/value pairs in schema order" do
      assert NBPR.Dnsmasq.Dnsmasq.argv(config_file: "/etc/dnsmasq.conf") ==
               [
                 "--conf-file",
                 "/etc/dnsmasq.conf",
                 "--keep-in-foreground",
                 "--pid-file",
                 "/run/dnsmasq.pid",
                 "--log-facility",
                 "-"
               ]
    end

    test "argv omits boolean flags when false" do
      argv =
        NBPR.Dnsmasq.Dnsmasq.argv(
          config_file: "/etc/dnsmasq.conf",
          keep_in_foreground: false
        )

      refute "--keep-in-foreground" in argv
    end

    test "argv raises when config_file is missing" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NBPR.Dnsmasq.Dnsmasq.argv([])
      end
    end
  end
end
