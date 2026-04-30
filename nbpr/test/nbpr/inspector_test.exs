defmodule NBPR.InspectorTest do
  use ExUnit.Case, async: true

  defmodule Daemonless do
    use NBPR.BrPackage,
      version: 1,
      br_package: "jq",
      description: "Lightweight JSON processor",
      homepage: "https://jqlang.github.io/jq/",
      build_opts: [
        oniguruma: [
          type: :boolean,
          default: true,
          br_flag: "BR2_PACKAGE_JQ_ONIGURUMA",
          doc: "Enable Oniguruma regex support"
        ]
      ]
  end

  defmodule WithDaemon do
    use NBPR.BrPackage,
      version: 1,
      br_package: "dnsmasq",
      description: "Lightweight DHCP/DNS server",
      daemons: [
        dnsmasq: [
          path: "/usr/sbin/dnsmasq",
          opts: [
            config_file: [type: :string, required: true, flag: "--conf-file", doc: "Config path"],
            keep_in_foreground: [type: :boolean, default: true, flag: "--keep-in-foreground"]
          ]
        ]
      ],
      kernel_modules: ["nf_conntrack"]
  end

  describe "format/1" do
    test "renders header for daemonless package" do
      output = Daemonless.__nbpr_package__() |> NBPR.Inspector.format()

      assert output =~ "Package:     :nbpr_daemonless"
      assert output =~ "Module:      NBPR.InspectorTest.Daemonless"
      assert output =~ "Version:     1"
      assert output =~ "BR source:   jq (mainline Buildroot)"
      assert output =~ "Description: Lightweight JSON processor"
      assert output =~ "Homepage:    https://jqlang.github.io/jq/"
    end

    test "renders build opts with type, default, BR flag, and doc" do
      output = Daemonless.__nbpr_package__() |> NBPR.Inspector.format()

      assert output =~ "Build options:"
      assert output =~ "oniguruma (:boolean, default: true)"
      assert output =~ "BR flag: BR2_PACKAGE_JQ_ONIGURUMA"
      assert output =~ "Enable Oniguruma regex support"
    end

    test "renders '(none)' placeholders for empty sections" do
      output = Daemonless.__nbpr_package__() |> NBPR.Inspector.format()

      assert output =~ "Daemons: (none)"
      assert output =~ "Kernel modules: (none)"
    end

    test "renders daemon block with module, path, argv template, and runtime opts" do
      output = WithDaemon.__nbpr_package__() |> NBPR.Inspector.format()

      assert output =~ "Daemons:"
      assert output =~ "dnsmasq → NBPR.InspectorTest.WithDaemon.Dnsmasq"
      assert output =~ "Path:           /usr/sbin/dnsmasq"
      assert output =~ "Argv template:  NBPR.BrPackage.default_argv"
      assert output =~ "config_file (:string, required)"
      assert output =~ "Flag: --conf-file"
      assert output =~ "keep_in_foreground (:boolean, default: true)"
      assert output =~ "Flag: --keep-in-foreground"
    end

    test "renders kernel modules list when populated" do
      output = WithDaemon.__nbpr_package__() |> NBPR.Inspector.format()

      assert output =~ "Kernel modules:"
      assert output =~ "  nf_conntrack"
    end

    test "renders 'source-build only' when artifact_sites is empty" do
      output = Daemonless.__nbpr_package__() |> NBPR.Inspector.format()
      assert output =~ "Artifact sites: (none — source-build only)"
    end
  end

  describe "format/1 — artifact_sites" do
    defmodule WithSites do
      use NBPR.BrPackage,
        version: 1,
        br_package: "jq",
        description: "test",
        artifact_sites: [{:github_releases, "jimsynz/nbpr"}]
    end

    test "renders github_releases sites" do
      output = WithSites.__nbpr_package__() |> NBPR.Inspector.format()
      assert output =~ "Artifact sites:"
      assert output =~ "github_releases: jimsynz/nbpr"
    end
  end
end
