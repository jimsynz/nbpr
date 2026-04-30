defmodule NBPR.Buildroot.DefconfigTest do
  use ExUnit.Case, async: true

  alias NBPR.Buildroot.Defconfig

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "nbpr_defconfig_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "br_symbol/1" do
    test "uppercases and replaces dashes with underscores" do
      assert Defconfig.br_symbol("jq") == "JQ"
      assert Defconfig.br_symbol("dnsmasq") == "DNSMASQ"
      assert Defconfig.br_symbol("wireguard-tools") == "WIREGUARD_TOOLS"
      assert Defconfig.br_symbol("tpm2-tss") == "TPM2_TSS"
    end
  end

  describe "format_br_value/1" do
    test "booleans become y / n" do
      assert Defconfig.format_br_value(true) == "y"
      assert Defconfig.format_br_value(false) == "n"
    end

    test "integers stringify" do
      assert Defconfig.format_br_value(42) == "42"
    end

    test "strings get quoted" do
      assert Defconfig.format_br_value("normal") == ~s("normal")
    end
  end

  describe "render!/3" do
    test "appends a BR2_PACKAGE_<NAME>=y line and PER_PACKAGE marker", %{tmp: tmp} do
      sys_defconfig = Path.join(tmp, "nerves_defconfig")
      File.write!(sys_defconfig, "BR2_arm=y\nBR2_TOOLCHAIN_EXTERNAL=y\n")

      package = %NBPR.Package{
        name: :jq,
        version: 1,
        module: NBPR.Jq,
        description: "x",
        br_package: "jq",
        build_opts: [],
        build_opt_extensions: %{},
        daemons: [],
        kernel_modules: [],
        artifact_sites: []
      }

      out = Defconfig.render!(package, sys_defconfig, [])

      assert out =~ "BR2_arm=y"
      assert out =~ "BR2_PER_PACKAGE_DIRECTORIES=y"
      assert out =~ "BR2_PACKAGE_JQ=y"
      assert String.ends_with?(out, "\n")
    end

    test "emits one BR config line per resolved build_opt with a :br_flag", %{tmp: tmp} do
      sys_defconfig = Path.join(tmp, "nerves_defconfig")
      File.write!(sys_defconfig, "BR2_arm=y\n")

      package = %NBPR.Package{
        name: :jq,
        version: 1,
        module: NBPR.Jq,
        description: "x",
        br_package: "jq",
        build_opts: [],
        build_opt_extensions: %{
          oniguruma: %{br_flag: "BR2_PACKAGE_JQ_ONIGURUMA"},
          loglevel: %{br_flag: "BR2_PACKAGE_JQ_LOGLEVEL"},
          # An opt without :br_flag — should be skipped.
          docs_only: %{}
        },
        daemons: [],
        kernel_modules: [],
        artifact_sites: []
      }

      out =
        Defconfig.render!(package, sys_defconfig,
          oniguruma: true,
          loglevel: "info",
          docs_only: true
        )

      assert out =~ ~r/^BR2_PACKAGE_JQ_ONIGURUMA=y$/m
      assert out =~ ~r/^BR2_PACKAGE_JQ_LOGLEVEL="info"$/m
      refute out =~ "docs_only"
    end

    test "preserves and follows the system defconfig contents", %{tmp: tmp} do
      sys_defconfig = Path.join(tmp, "nerves_defconfig")
      content = "BR2_arm=y\nBR2_aarch64=y\nBR2_TARGET_ROOTFS_SQUASHFS=y\n"
      File.write!(sys_defconfig, content)

      package = %NBPR.Package{
        name: :jq,
        version: 1,
        module: NBPR.Jq,
        description: "x",
        br_package: "jq",
        build_opts: [],
        build_opt_extensions: %{},
        daemons: [],
        kernel_modules: [],
        artifact_sites: []
      }

      out = Defconfig.render!(package, sys_defconfig, [])
      assert String.starts_with?(out, content)
    end
  end
end
