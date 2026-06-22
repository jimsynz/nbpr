defmodule NBPR.Linux.HarvestTest do
  use ExUnit.Case, async: true

  alias NBPR.Linux.Harvest

  setup do
    root = Path.join(System.tmp_dir!(), "nbpr_harvest_#{System.unique_integer([:positive])}")
    out = Path.join(root, "out")
    File.mkdir_p!(Path.join(out, "images"))
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root, out: out}
  end

  test "collects the kernel image and device trees into boot/", ctx do
    File.write!(Path.join(ctx.out, "images/Image"), "KERNEL")
    File.write!(Path.join(ctx.out, "images/board.dtb"), "DTB")
    File.write!(Path.join(ctx.out, "images/overlay.dtbo"), "DTBO")
    # Non-kernel cruft that must NOT be harvested.
    File.write!(Path.join(ctx.out, "images/config.txt"), "x")

    dest = Path.join(ctx.root, "dest")
    sources = Harvest.collect!(ctx.out, dest)

    boot = Map.fetch!(sources, :boot)
    assert File.read!(Path.join(boot, "Image")) == "KERNEL"
    assert File.exists?(Path.join(boot, "board.dtb"))
    assert File.exists?(Path.join(boot, "overlay.dtbo"))
    refute File.exists?(Path.join(boot, "config.txt"))
  end

  test "collects modules into rootfs/lib/modules", ctx do
    File.write!(Path.join(ctx.out, "images/zImage"), "KERNEL")
    mod_dir = Path.join(ctx.out, "target/lib/modules/6.12.0")
    File.mkdir_p!(mod_dir)
    File.write!(Path.join(mod_dir, "foo.ko"), "MODULE")

    dest = Path.join(ctx.root, "dest")
    sources = Harvest.collect!(ctx.out, dest)

    rootfs = Map.fetch!(sources, :rootfs)
    assert File.read!(Path.join(rootfs, "lib/modules/6.12.0/foo.ko")) == "MODULE"
  end

  test "omits rootfs when there are no modules", ctx do
    File.write!(Path.join(ctx.out, "images/Image"), "KERNEL")

    sources = Harvest.collect!(ctx.out, Path.join(ctx.root, "dest"))
    refute Map.has_key?(sources, :rootfs)
  end

  test "raises when no kernel image is present", ctx do
    File.write!(Path.join(ctx.out, "images/board.dtb"), "DTB")

    assert_raise RuntimeError, ~r/no kernel image/, fn ->
      Harvest.collect!(ctx.out, Path.join(ctx.root, "dest"))
    end
  end
end
