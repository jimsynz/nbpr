defmodule NBPR.Linux.ShadowTest do
  use ExUnit.Case, async: true

  alias NBPR.Linux.Shadow

  setup do
    root = Path.join(System.tmp_dir!(), "nbpr_shadow_#{System.unique_integer([:positive])}")

    system = Path.join(root, "system")
    File.mkdir_p!(Path.join(system, "images"))
    File.mkdir_p!(Path.join(system, "scripts"))
    File.write!(Path.join(system, "scripts/rel2fw.sh"), "#!/bin/sh\n")
    File.write!(Path.join(system, "images/Image"), "STOCK-KERNEL")
    File.write!(Path.join(system, "images/board.dtb"), "STOCK-DTB")
    File.write!(Path.join(system, "images/rootfs.squashfs"), "SQUASHFS")

    boot = Path.join(root, "boot")
    File.mkdir_p!(boot)
    File.write!(Path.join(boot, "Image"), "CUSTOM-KERNEL")
    File.write!(Path.join(boot, "board.dtb"), "CUSTOM-DTB")

    shadow = Path.join(root, "shadow")

    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, system: system, boot: boot, shadow: shadow}
  end

  test "overrides kernel image/DTBs but symlinks everything else", ctx do
    Shadow.build!(ctx.system, ctx.boot, ctx.shadow)

    # Kernel + DTB resolve to the custom boot files.
    assert File.read!(Path.join(ctx.shadow, "images/Image")) == "CUSTOM-KERNEL"
    assert File.read!(Path.join(ctx.shadow, "images/board.dtb")) == "CUSTOM-DTB"

    # Untouched images and sibling dirs resolve back to the real system.
    assert File.read!(Path.join(ctx.shadow, "images/rootfs.squashfs")) == "SQUASHFS"
    assert File.read!(Path.join(ctx.shadow, "scripts/rel2fw.sh")) == "#!/bin/sh\n"
  end

  test "never mutates the source system", ctx do
    Shadow.build!(ctx.system, ctx.boot, ctx.shadow)

    assert File.read!(Path.join(ctx.system, "images/Image")) == "STOCK-KERNEL"
    refute File.lstat!(Path.join(ctx.system, "images/Image")).type == :symlink
  end

  test "is idempotent across rebuilds", ctx do
    Shadow.build!(ctx.system, ctx.boot, ctx.shadow)
    Shadow.build!(ctx.system, ctx.boot, ctx.shadow)

    assert File.read!(Path.join(ctx.shadow, "images/Image")) == "CUSTOM-KERNEL"
  end
end
