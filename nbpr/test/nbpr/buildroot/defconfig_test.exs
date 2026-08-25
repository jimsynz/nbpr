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

  describe "render!/4" do
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

      out = Defconfig.render!(package, sys_defconfig, top_level_tree(tmp, "jq"), [])

      assert out =~ "BR2_arm=y"
      assert out =~ "BR2_PER_PACKAGE_DIRECTORIES=y"
      assert out =~ "BR2_PACKAGE_BUSYBOX_SHOW_OTHERS=y"
      assert out =~ "BR2_PACKAGE_JQ=y"
      assert String.ends_with?(out, "\n")
    end

    # Nerves systems point BR2_BACKUP_SITE at their own mirror, which only
    # carries what a Nerves system builds — so without a primary site an nbpr
    # build's only real source is the package's own upstream, and gpsd's
    # (a Savannah mirror over plain HTTP) times out often enough from CI to
    # fail half a nine-target matrix.
    test "points the primary download site at Buildroot's source archive", %{tmp: tmp} do
      sys_defconfig = Path.join(tmp, "nerves_defconfig")
      File.write!(sys_defconfig, ~s(BR2_arm=y\nBR2_BACKUP_SITE="https://dl.nerves-project.org"\n))

      package = %NBPR.Package{
        name: :gpsd,
        version: 1,
        module: NBPR.Gpsd,
        description: "x",
        br_package: "gpsd",
        build_opts: [],
        build_opt_extensions: %{},
        daemons: [],
        kernel_modules: [],
        artifact_sites: []
      }

      out = Defconfig.render!(package, sys_defconfig, top_level_tree(tmp, "gpsd"), [])

      assert out =~ ~s(BR2_PRIMARY_SITE="https://sources.buildroot.net")

      # The system's own backup choice is left intact — this adds a source
      # ahead of upstream rather than replacing the fallback behind it.
      assert out =~ ~s(BR2_BACKUP_SITE="https://dl.nerves-project.org")
      refute out =~ "BR2_PRIMARY_SITE_ONLY"
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
        Defconfig.render!(package, sys_defconfig, top_level_tree(tmp, "jq"),
          oniguruma: true,
          loglevel: "info",
          docs_only: true
        )

      assert out =~ ~r/^BR2_PACKAGE_JQ_ONIGURUMA=y$/m
      assert out =~ ~r/^BR2_PACKAGE_JQ_LOGLEVEL="info"$/m
      refute out =~ "docs_only"
    end

    # Buildroot models JPEG as a virtual package: `BR2_PACKAGE_JPEG` plus a
    # provider from the `choice` beneath it. Leaving the provider to kconfig's
    # default picks turbo only where SIMD is supported, so an ARMv6 target
    # would silently build IJG libjpeg — a different soname.
    test "a :br_flag naming several symbols emits a line for each", %{tmp: tmp} do
      sys_defconfig = Path.join(tmp, "nerves_defconfig")
      File.write!(sys_defconfig, "BR2_arm=y\n")

      package = %NBPR.Package{
        name: :imagemagick,
        version: 1,
        module: NBPR.Imagemagick,
        description: "x",
        br_package: "imagemagick",
        build_opts: [],
        build_opt_extensions: %{
          jpeg: %{br_flag: ["BR2_PACKAGE_JPEG", "BR2_PACKAGE_JPEG_TURBO"]}
        },
        daemons: [],
        kernel_modules: [],
        artifact_sites: []
      }

      out =
        Defconfig.render!(package, sys_defconfig, top_level_tree(tmp, "imagemagick"), jpeg: true)

      assert out =~ ~r/^BR2_PACKAGE_JPEG=y$/m
      assert out =~ ~r/^BR2_PACKAGE_JPEG_TURBO=y$/m
    end

    test "a :br_flag list carries a false value to every symbol", %{tmp: tmp} do
      sys_defconfig = Path.join(tmp, "nerves_defconfig")
      File.write!(sys_defconfig, "BR2_arm=y\n")

      package = %NBPR.Package{
        name: :imagemagick,
        version: 1,
        module: NBPR.Imagemagick,
        description: "x",
        br_package: "imagemagick",
        build_opts: [],
        build_opt_extensions: %{
          jpeg: %{br_flag: ["BR2_PACKAGE_JPEG", "BR2_PACKAGE_JPEG_TURBO"]}
        },
        daemons: [],
        kernel_modules: [],
        artifact_sites: []
      }

      out =
        Defconfig.render!(package, sys_defconfig, top_level_tree(tmp, "imagemagick"), jpeg: false)

      assert out =~ ~r/^BR2_PACKAGE_JPEG=n$/m
      assert out =~ ~r/^BR2_PACKAGE_JPEG_TURBO=n$/m
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

      out = Defconfig.render!(package, sys_defconfig, top_level_tree(tmp, "jq"), [])
      assert String.starts_with?(out, content)
    end
  end

  describe "gating_symbols/2" do
    test "a top-level package is gated by nothing", %{tmp: tmp} do
      assert Defconfig.gating_symbols(top_level_tree(tmp, "jq"), "jq") == []
    end

    test "a package Buildroot doesn't have is gated by nothing", %{tmp: tmp} do
      assert Defconfig.gating_symbols(top_level_tree(tmp, "jq"), "nonesuch") == []
    end

    test "a nested package picks up the `if` enclosing its source line", %{tmp: tmp} do
      tree =
        nested_tree(tmp, "fftw", "fftw-single", """
        config BR2_PACKAGE_FFTW
        \tbool "fftw"

        if BR2_PACKAGE_FFTW

        source "package/fftw/fftw-single/Config.in"
        source "package/fftw/fftw-double/Config.in"

        endif
        """)

      assert Defconfig.gating_symbols(tree, "fftw-single") == ["BR2_PACKAGE_FFTW"]
    end

    test "nested `if` blocks accumulate, outermost first", %{tmp: tmp} do
      tree =
        nested_tree(tmp, "x11r7", "xdriver_xf86-video-fbdev", """
        menuconfig BR2_PACKAGE_XORG7

        if BR2_PACKAGE_XORG7
        \tif BR2_PACKAGE_XSERVER_XORG_SERVER_MODULAR
        \t\tsource "package/x11r7/xdriver_xf86-video-fbdev/Config.in"
        \tendif
        endif
        """)

      assert Defconfig.gating_symbols(tree, "xdriver_xf86-video-fbdev") ==
               ["BR2_PACKAGE_XORG7", "BR2_PACKAGE_XSERVER_XORG_SERVER_MODULAR"]
    end

    test "a nested package sourced unconditionally is gated by nothing", %{tmp: tmp} do
      tree =
        nested_tree(tmp, "opengl", "libgl", """
        source "package/opengl/libgl/Config.in"
        source "package/opengl/libegl/Config.in"
        """)

      assert Defconfig.gating_symbols(tree, "libgl") == []
    end

    test "an `if` block closed before the source line doesn't leak into it", %{tmp: tmp} do
      tree =
        nested_tree(tmp, "opengl", "libgl", """
        if BR2_PACKAGE_SOMETHING_ELSE
        source "package/opengl/libegl/Config.in"
        endif

        source "package/opengl/libgl/Config.in"
        """)

      assert Defconfig.gating_symbols(tree, "libgl") == []
    end

    # `package/jpeg-turbo/` holds only a `.mk` and `Config.in.options` — the
    # symbol is declared in the sibling `package/jpeg/Config.in`, inside a
    # `choice` under `if BR2_PACKAGE_JPEG`. Without the enclosing `if`,
    # `make olddefconfig` drops BR2_PACKAGE_JPEG_TURBO and the build silently
    # produces no per-package output.
    test "a symbol declared in a sibling package's Config.in picks up its `if`", %{tmp: tmp} do
      tree = Path.join(tmp, "br")
      File.mkdir_p!(Path.join([tree, "package", "jpeg-turbo"]))
      File.write!(Path.join([tree, "package", "jpeg-turbo", "Config.in.options"]), "")

      File.mkdir_p!(Path.join([tree, "package", "jpeg"]))

      File.write!(Path.join([tree, "package", "jpeg", "Config.in"]), """
      config BR2_PACKAGE_JPEG
      \tbool "jpeg support"

      if BR2_PACKAGE_JPEG

      choice
      \tprompt "jpeg variant"

      config BR2_PACKAGE_LIBJPEG
      \tbool "jpeg"

      config BR2_PACKAGE_JPEG_TURBO
      \tbool "jpeg-turbo"

      endchoice

      endif
      """)

      assert Defconfig.gating_symbols(tree, "jpeg-turbo") == ["BR2_PACKAGE_JPEG"]
    end

    # Buildroot has exactly one of these, an `||` over two freescale-imx
    # platform choices. Picking an arm isn't ours to do, so it's dropped —
    # while the plain symbol wrapping it is still emitted.
    test "a compound condition is dropped, its bare-symbol parent kept", %{tmp: tmp} do
      tree =
        nested_tree(tmp, "freescale-imx", "gpu-amd-bin-mx51", """
        if BR2_PACKAGE_FREESCALE_IMX
        if (BR2_PACKAGE_FREESCALE_IMX_PLATFORM_IMX51 || BR2_PACKAGE_FREESCALE_IMX_PLATFORM_IMX53)
        source "package/freescale-imx/gpu-amd-bin-mx51/Config.in"
        endif
        endif
        """)

      assert Defconfig.gating_symbols(tree, "gpu-amd-bin-mx51") ==
               ["BR2_PACKAGE_FREESCALE_IMX"]
    end
  end

  describe "render!/4 with a nested package" do
    test "emits the gating symbol before the package's own", %{tmp: tmp} do
      sys_defconfig = Path.join(tmp, "nerves_defconfig")
      File.write!(sys_defconfig, "BR2_arm=y\n")

      tree =
        nested_tree(tmp, "fftw", "fftw-single", """
        if BR2_PACKAGE_FFTW
        source "package/fftw/fftw-single/Config.in"
        endif
        """)

      package = %NBPR.Package{
        name: :fftw_single,
        version: 1,
        module: NBPR.FftwSingle,
        description: "x",
        br_package: "fftw-single",
        build_opts: [],
        build_opt_extensions: %{},
        daemons: [],
        kernel_modules: [],
        artifact_sites: []
      }

      out = Defconfig.render!(package, sys_defconfig, tree, [])

      assert out =~ ~r/^BR2_PACKAGE_FFTW=y$/m
      assert out =~ ~r/^BR2_PACKAGE_FFTW_SINGLE=y$/m

      gate = :binary.match(out, "BR2_PACKAGE_FFTW=y") |> elem(0)
      own = :binary.match(out, "BR2_PACKAGE_FFTW_SINGLE=y") |> elem(0)
      assert gate < own
    end
  end

  defp top_level_tree(tmp, name) do
    tree = Path.join(tmp, "br")
    dir = Path.join([tree, "package", name])
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "Config.in"), declaration(name))
    tree
  end

  defp nested_tree(tmp, parent, child, parent_config) do
    tree = Path.join(tmp, "br")
    child_dir = Path.join([tree, "package", parent, child])
    File.mkdir_p!(child_dir)
    File.write!(Path.join(child_dir, "Config.in"), declaration(child))
    File.write!(Path.join([tree, "package", parent, "Config.in"]), parent_config)
    tree
  end

  # A package's own `Config.in` declares its symbol; the gate lookup starts
  # from the declaration, so a stub that omits it isn't a faithful fixture.
  defp declaration(name) do
    ~s(config BR2_PACKAGE_#{Defconfig.br_symbol(name)}\n\tbool "#{name}"\n)
  end
end
