defmodule NBPR.Linux.DefconfigTest do
  use ExUnit.Case, async: true

  alias NBPR.Linux.Defconfig

  @system_defconfig """
  BR2_arm=y
  BR2_LINUX_KERNEL=y
  BR2_LINUX_KERNEL_CUSTOM_TARBALL=y
  BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION="https://example.test/linux.tar.gz"
  BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y
  """

  describe "render/3 with no extras" do
    test "returns the base unchanged but newline-terminated" do
      assert Defconfig.render(@system_defconfig, [], []) == @system_defconfig
    end

    test "leaves the kernel version (tarball location) untouched" do
      rendered = Defconfig.render(@system_defconfig, ["/x/frag"], ["/x/patch"])

      assert rendered =~
               ~s(BR2_LINUX_KERNEL_CUSTOM_TARBALL_LOCATION="https://example.test/linux.tar.gz")
    end
  end

  describe "render/3 fragments and patches" do
    test "emits fragment and patch lines pointing at the given paths" do
      rendered = Defconfig.render(@system_defconfig, ["/cfg/a.fragment"], ["/cfg/0001.patch"])

      assert rendered =~ ~s(BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="/cfg/a.fragment")
      assert rendered =~ ~s(BR2_LINUX_KERNEL_PATCH="/cfg/0001.patch")
    end

    test "joins multiple paths with spaces" do
      rendered = Defconfig.render(@system_defconfig, ["/a.fragment", "/b.fragment"], [])
      assert rendered =~ ~s(BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="/a.fragment /b.fragment")
    end

    test "omits a var when its list is empty" do
      rendered = Defconfig.render(@system_defconfig, ["/a.fragment"], [])
      refute rendered =~ "BR2_LINUX_KERNEL_PATCH="
    end
  end

  describe "render/3 merges with an existing value (no clobber)" do
    test "appends to a pre-existing BR2_LINUX_KERNEL_PATCH" do
      base = @system_defconfig <> ~s(BR2_LINUX_KERNEL_PATCH="/system/linux"\n)
      rendered = Defconfig.render(base, [], ["/user/0001.patch"])

      assert rendered =~ ~s(BR2_LINUX_KERNEL_PATCH="/system/linux /user/0001.patch")
    end

    test "does not duplicate a path already present" do
      base = @system_defconfig <> ~s(BR2_LINUX_KERNEL_PATCH="/system/linux"\n)
      rendered = Defconfig.render(base, [], ["/system/linux", "/user/0001.patch"])

      assert rendered =~ ~s(BR2_LINUX_KERNEL_PATCH="/system/linux /user/0001.patch")
    end
  end

  describe "existing_values/2" do
    test "parses a space-separated quoted value" do
      base = ~s(BR2_LINUX_KERNEL_PATCH="/a /b /c"\n)
      assert Defconfig.existing_values(base, "BR2_LINUX_KERNEL_PATCH") == ["/a", "/b", "/c"]
    end

    test "returns [] when the var is absent" do
      assert Defconfig.existing_values("BR2_arm=y\n", "BR2_LINUX_KERNEL_PATCH") == []
    end
  end
end
