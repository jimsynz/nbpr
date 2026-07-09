defmodule NBPR.RuntimeTest do
  use ExUnit.Case, async: true

  describe "on_nerves_target?/0" do
    test "returns false on the dev host" do
      refute NBPR.Runtime.on_nerves_target?()
    end
  end

  describe "on_nerves_target?/1" do
    @tag :tmp_dir
    test "true when os-release declares ID=nerves", %{tmp_dir: tmp} do
      path = Path.join(tmp, "os-release")

      File.write!(path, """
      NAME=Nerves
      ID=nerves
      NERVES_SYSTEM_NAME=nerves_system_rpi5
      """)

      assert NBPR.Runtime.on_nerves_target?(path)
    end

    @tag :tmp_dir
    test "accepts a quoted ID value", %{tmp_dir: tmp} do
      path = Path.join(tmp, "os-release")
      File.write!(path, ~s(ID="nerves"\n))

      assert NBPR.Runtime.on_nerves_target?(path)
    end

    @tag :tmp_dir
    test "false for a non-Nerves os-release", %{tmp_dir: tmp} do
      path = Path.join(tmp, "os-release")

      File.write!(path, """
      NAME="Debian GNU/Linux"
      ID=debian
      """)

      refute NBPR.Runtime.on_nerves_target?(path)
    end

    test "false when the file is missing" do
      refute NBPR.Runtime.on_nerves_target?("/nonexistent/os-release")
    end
  end

  describe "find_module/2" do
    @tag :tmp_dir
    test "locates a .ko under lib/modules", %{tmp_dir: priv} do
      ko = Path.join(priv, "lib/modules/6.18.33-v8/extra/hailo1x_pci.ko")
      File.mkdir_p!(Path.dirname(ko))
      File.write!(ko, "")

      assert NBPR.Runtime.find_module(priv, "hailo1x_pci") == ko
    end

    @tag :tmp_dir
    test "treats hyphens and underscores as equivalent", %{tmp_dir: priv} do
      ko = Path.join(priv, "lib/modules/6.18.33-v8/extra/spi-my-driver.ko")
      File.mkdir_p!(Path.dirname(ko))
      File.write!(ko, "")

      assert NBPR.Runtime.find_module(priv, "spi_my_driver") == ko
    end

    @tag :tmp_dir
    test "finds compressed modules", %{tmp_dir: priv} do
      ko = Path.join(priv, "lib/modules/6.18.33-v8/extra/zstd_thing.ko.xz")
      File.mkdir_p!(Path.dirname(ko))
      File.write!(ko, "")

      assert NBPR.Runtime.find_module(priv, "zstd_thing") == ko
    end

    @tag :tmp_dir
    test "nil when the module isn't shipped", %{tmp_dir: priv} do
      assert NBPR.Runtime.find_module(priv, "not_here") == nil
    end

    test "nil for a nil priv dir" do
      assert NBPR.Runtime.find_module(nil, "anything") == nil
    end
  end

  describe "modprobe!/1" do
    test "raises with non-zero exit and stderr included" do
      assert_raise RuntimeError, ~r/modprobe .* failed/, fn ->
        NBPR.Runtime.modprobe!("__nbpr_definitely_not_a_real_module__")
      end
    end
  end

  describe "load_kernel_module!/2" do
    test "falls back to modprobe when the package ships no .ko" do
      assert_raise RuntimeError, ~r/modprobe .* failed/, fn ->
        NBPR.Runtime.load_kernel_module!(:nbpr, "__nbpr_definitely_not_a_real_module__")
      end
    end
  end
end
