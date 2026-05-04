defmodule NBPR.Buildroot.PackageTest do
  use ExUnit.Case, async: true

  alias NBPR.Buildroot.Package

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "nbpr_br_pkg_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp, "package"))
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, br_tree: tmp}
  end

  describe "read/2" do
    test "extracts version, licences, and Config.in title/help", %{br_tree: br_tree} do
      write_pkg!(br_tree, "iperf3",
        mk: """
        IPERF3_VERSION = 3.19.1
        IPERF3_SOURCE = iperf-$(IPERF3_VERSION).tar.gz
        IPERF3_SITE = https://downloads.es.net/pub/iperf/
        IPERF3_LICENSE = BSD-3-Clause, BSD-2-Clause, MIT
        IPERF3_LICENSE_FILES = LICENSE
        $(eval $(autotools-package))
        """,
        config_in: """
        config BR2_PACKAGE_IPERF3
        \tbool "iperf3"
        \tdepends on BR2_TOOLCHAIN_HAS_THREADS
        \thelp
        \t  iperf is a tool for active measurements of the maximum
        \t  achievable bandwidth on IP networks.
        \t  It supports tuning of various parameters.

        \t  http://software.es.net/iperf/index.html
        """
      )

      assert {:ok, pkg} = Package.read(br_tree, "iperf3")

      assert pkg.name == "iperf3"
      assert pkg.version == "3.19.1"
      assert pkg.licences == ["BSD-3-Clause", "BSD-2-Clause", "MIT"]
      assert pkg.title == "iperf3"

      assert pkg.description ==
               "Iperf is a tool for active measurements of the maximum achievable bandwidth on IP networks."

      assert pkg.homepage == "http://software.es.net/iperf/index.html"
      assert pkg.help =~ "iperf is a tool"
      assert pkg.help =~ "http://software.es.net/iperf"
    end

    test "falls back to <NAME>_SITE when help has no URL", %{br_tree: br_tree} do
      write_pkg!(br_tree, "thing",
        mk: """
        THING_VERSION = 1.2.3
        THING_SITE = https://example.com/thing
        THING_LICENSE = MIT
        """,
        config_in: """
        config BR2_PACKAGE_THING
        \tbool "thing"
        \thelp
        \t  thing does the thing.
        """
      )

      assert {:ok, pkg} = Package.read(br_tree, "thing")
      assert pkg.homepage == "https://example.com/thing"
    end

    test "handles hyphenated package names by mapping to underscored prefix",
         %{br_tree: br_tree} do
      write_pkg!(br_tree, "kernel-modules",
        mk: """
        KERNEL_MODULES_VERSION = 1.0
        KERNEL_MODULES_LICENSE = GPL-2.0
        """,
        config_in: """
        config BR2_PACKAGE_KERNEL_MODULES
        \tbool "kernel-modules"
        \thelp
        \t  Out-of-tree kernel modules.
        """
      )

      assert {:ok, pkg} = Package.read(br_tree, "kernel-modules")
      assert pkg.version == "1.0"
      assert pkg.title == "kernel-modules"
    end

    test "returns :package_not_found when the dir is absent", %{br_tree: br_tree} do
      assert {:error, :package_not_found} = Package.read(br_tree, "nope")
    end

    test "returns :mk_not_found when the dir exists but the .mk doesn't",
         %{br_tree: br_tree} do
      File.mkdir_p!(Path.join([br_tree, "package", "weird"]))
      assert {:error, :mk_not_found} = Package.read(br_tree, "weird")
    end

    test "returns :missing_var when _VERSION is absent", %{br_tree: br_tree} do
      write_pkg!(br_tree, "broken",
        mk: """
        BROKEN_LICENSE = MIT
        """,
        config_in: ""
      )

      assert {:error, {:missing_var, "BROKEN_VERSION"}} = Package.read(br_tree, "broken")
    end

    test "extracts target dependencies from _DEPENDENCIES and `select` lines",
         %{br_tree: br_tree} do
      write_pkg!(br_tree, "tcpdump",
        mk: """
        TCPDUMP_VERSION = 4.99.5
        TCPDUMP_LICENSE = BSD-3-Clause
        TCPDUMP_DEPENDENCIES = libpcap host-pkgconf
        """,
        config_in: """
        config BR2_PACKAGE_TCPDUMP
        \tbool "tcpdump"
        \tselect BR2_PACKAGE_LIBPCAP
        \thelp
        \t  A network sniffer.
        """
      )

      assert {:ok, pkg} = Package.read(br_tree, "tcpdump")
      assert pkg.dependencies == ["libpcap"]
    end

    test "filters host-* deps and $(...) make-variable refs", %{br_tree: br_tree} do
      write_pkg!(br_tree, "dnsmasq",
        mk: """
        DNSMASQ_VERSION = 2.91
        DNSMASQ_LICENSE = GPL-2.0
        DNSMASQ_DEPENDENCIES = host-pkgconf $(TARGET_NLS_DEPENDENCIES)
        """,
        config_in: """
        config BR2_PACKAGE_DNSMASQ
        \tbool "dnsmasq"
        \thelp
        \t  DHCP/DNS server.
        """
      )

      assert {:ok, pkg} = Package.read(br_tree, "dnsmasq")
      assert pkg.dependencies == []
    end

    test "ignores conditional _DEPENDENCIES += lines", %{br_tree: br_tree} do
      write_pkg!(br_tree, "strace",
        mk: """
        STRACE_VERSION = 6.18
        STRACE_LICENSE = LGPL-2.1+
        ifeq ($(BR2_PACKAGE_LIBUNWIND),y)
        STRACE_DEPENDENCIES += libunwind
        endif
        """,
        config_in: """
        config BR2_PACKAGE_STRACE
        \tbool "strace"
        \thelp
        \t  Trace system calls.
        """
      )

      assert {:ok, pkg} = Package.read(br_tree, "strace")
      assert pkg.dependencies == []
    end

    test "deduplicates deps that appear in both _DEPENDENCIES and `select`",
         %{br_tree: br_tree} do
      write_pkg!(br_tree, "thing",
        mk: """
        THING_VERSION = 1.0
        THING_LICENSE = MIT
        THING_DEPENDENCIES = libpcap
        """,
        config_in: """
        config BR2_PACKAGE_THING
        \tbool "thing"
        \tselect BR2_PACKAGE_LIBPCAP
        \thelp
        \t  Whatever.
        """
      )

      assert {:ok, pkg} = Package.read(br_tree, "thing")
      assert pkg.dependencies == ["libpcap"]
    end

    test "tolerates Config.in missing entirely", %{br_tree: br_tree} do
      pkg_dir = Path.join([br_tree, "package", "minimal"])
      File.mkdir_p!(pkg_dir)

      File.write!(Path.join(pkg_dir, "minimal.mk"), """
      MINIMAL_VERSION = 0.1
      MINIMAL_LICENSE = MIT
      MINIMAL_SITE = https://example.com/minimal
      """)

      assert {:ok, pkg} = Package.read(br_tree, "minimal")
      assert pkg.title == nil
      assert pkg.help == nil
      assert pkg.description == nil
      assert pkg.homepage == "https://example.com/minimal"
    end
  end

  defp write_pkg!(br_tree, name, mk: mk, config_in: config_in) do
    pkg_dir = Path.join([br_tree, "package", name])
    File.mkdir_p!(pkg_dir)
    File.write!(Path.join(pkg_dir, "#{name}.mk"), mk)
    File.write!(Path.join(pkg_dir, "Config.in"), config_in)
  end
end
