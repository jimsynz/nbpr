defmodule NBPR.Buildroot.BuilderTest do
  use ExUnit.Case, async: true

  alias NBPR.Buildroot.Builder

  describe "libc_of_system/1" do
    test "reads musl from the system's toolchain kconfig" do
      system = system_with!("BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y\n")

      assert Builder.libc_of_system(system) == :musl
    end

    test "reads glibc as :gnu" do
      system = system_with!("BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC=y\n")

      assert Builder.libc_of_system(system) == :gnu
    end

    test "a commented-out musl line is not a musl system" do
      system = system_with!("# BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y is not set\n")

      assert Builder.libc_of_system(system) == :gnu
    end

    test "a toolchain URL mentioning musl doesn't override the kconfig" do
      # The x86_64 system names its toolchain `..._nerves_linux_musl`, but
      # kconfig is what decides what the package compiles against — so the
      # marker is the one being read, not the URL.
      system =
        system_with!("""
        BR2_TOOLCHAIN_EXTERNAL_URL="https://example.test/nerves_toolchain_x86_64_nerves_linux_musl.tar.xz"
        BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC=y
        """)

      assert Builder.libc_of_system(system) == :gnu
    end

    test "assumes glibc when there's no defconfig to read" do
      assert Builder.libc_of_system(tmp_dir!()) == :gnu
    end
  end

  describe "ensure_libc_supported!/3" do
    test "raises for a package that declares the system's libc unsupported" do
      system = system_with!("BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y\n")

      assert_raise Mix.Error, ~r/cannot be built against musl/, fn ->
        Builder.ensure_libc_supported!(package(unsupported_libc: [:musl]), system, :x86_64)
      end
    end

    test "the message names the system and points at the package's docs" do
      system = system_with!("BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y\n")

      error =
        assert_raise Mix.Error, fn ->
          Builder.ensure_libc_supported!(package(unsupported_libc: [:musl]), system, :x86_64)
        end

      assert error.message =~ "x86_64 uses musl"
      assert error.message =~ "NBPR.Test"
    end

    test "passes on a libc the package doesn't exclude" do
      system = system_with!("BR2_TOOLCHAIN_EXTERNAL_CUSTOM_GLIBC=y\n")

      assert Builder.ensure_libc_supported!(package(unsupported_libc: [:musl]), system, :rpi4) ==
               :ok
    end

    test "passes for a package that excludes nothing" do
      system = system_with!("BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y\n")

      assert Builder.ensure_libc_supported!(package(unsupported_libc: []), system, :x86_64) == :ok
    end
  end

  defp package(opts) do
    %NBPR.Package{
      name: :test,
      version: 1,
      module: NBPR.Test,
      description: "test",
      br_package: "test",
      build_opts: [],
      build_opt_extensions: %{},
      daemons: [],
      kernel_modules: [],
      runtime_env: [],
      unsupported_libc: Keyword.fetch!(opts, :unsupported_libc),
      artifact_sites: []
    }
  end

  defp system_with!(defconfig) do
    dir = tmp_dir!()
    File.write!(Path.join(dir, "nerves_defconfig"), defconfig)
    dir
  end

  defp tmp_dir! do
    dir = Path.join(System.tmp_dir!(), "nbpr-builder-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end
end
