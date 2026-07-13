defmodule NBPR.SysrootTest do
  # async: false — `repoint_env!/2` mutates the node-wide OS environment.
  use ExUnit.Case, async: false

  alias NBPR.Sysroot

  describe "system_shadow!/3" do
    setup do
      root = Path.join(System.tmp_dir!(), "nbpr_sysroot_#{System.unique_integer([:positive])}")

      system = Path.join(root, "system")
      File.mkdir_p!(Path.join(system, "scripts"))
      File.write!(Path.join(system, "scripts/rel2fw.sh"), "#!/bin/sh\n")

      staging = Path.join(system, "staging")
      File.mkdir_p!(Path.join(staging, "usr/lib/pkgconfig"))
      File.mkdir_p!(Path.join(staging, "usr/include"))
      File.write!(Path.join(staging, "usr/lib/libc.so"), "SYSTEM-LIBC")
      File.write!(Path.join(staging, "usr/lib/libsrtp2.so.1"), "SYSTEM-PLACEHOLDER")
      File.ln_s!("libsrtp2.so.1", Path.join(staging, "usr/lib/libsrtp2.so"))

      pkg = Path.join(root, "pkg_staging")
      File.mkdir_p!(Path.join(pkg, "usr/lib/pkgconfig"))
      File.mkdir_p!(Path.join(pkg, "usr/include"))
      File.write!(Path.join(pkg, "usr/lib/libsrtp2.so.1"), "PACKAGE-LIBSRTP")
      File.write!(Path.join(pkg, "usr/lib/pkgconfig/libsrtp2.pc"), "Name: libsrtp2\n")
      File.write!(Path.join(pkg, "usr/include/srtp.h"), "#define SRTP 1\n")

      shadow = Path.join(root, "shadow")

      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, system: system, staging: staging, pkg: pkg, shadow: shadow}
    end

    test "symlinks non-staging children back to the real system", ctx do
      Sysroot.system_shadow!(ctx.system, [], ctx.shadow)

      link = Path.join(ctx.shadow, "scripts")
      assert File.lstat!(link).type == :symlink
      assert File.read!(Path.join(ctx.shadow, "scripts/rel2fw.sh")) == "#!/bin/sh\n"
    end

    test "mirrors system staging as hardlinks, not symlinks", ctx do
      shadow_staging = Sysroot.system_shadow!(ctx.system, [], ctx.shadow)

      mirrored = Path.join(shadow_staging, "usr/lib/libc.so")
      assert File.lstat!(mirrored).type == :regular
      assert File.read!(mirrored) == "SYSTEM-LIBC"

      real = Path.join(ctx.staging, "usr/lib/libc.so")
      assert File.stat!(mirrored).inode == File.stat!(real).inode
    end

    test "preserves symlinks within staging", ctx do
      shadow_staging = Sysroot.system_shadow!(ctx.system, [], ctx.shadow)

      link = Path.join(shadow_staging, "usr/lib/libsrtp2.so")
      assert File.lstat!(link).type == :symlink
      assert File.read_link!(link) == "libsrtp2.so.1"
    end

    test "overlays package staging files onto the mirror", ctx do
      shadow_staging = Sysroot.system_shadow!(ctx.system, [ctx.pkg], ctx.shadow)

      assert File.read!(Path.join(shadow_staging, "usr/lib/libsrtp2.so.1")) == "PACKAGE-LIBSRTP"
      assert File.read!(Path.join(shadow_staging, "usr/include/srtp.h")) == "#define SRTP 1\n"

      assert File.read!(Path.join(shadow_staging, "usr/lib/pkgconfig/libsrtp2.pc")) ==
               "Name: libsrtp2\n"
    end

    test "never writes through to the real staging when overlaying", ctx do
      real = Path.join(ctx.staging, "usr/lib/libsrtp2.so.1")
      inode_before = File.stat!(real).inode

      Sysroot.system_shadow!(ctx.system, [ctx.pkg], ctx.shadow)

      assert File.read!(real) == "SYSTEM-PLACEHOLDER"
      assert File.stat!(real).inode == inode_before
    end

    test "is idempotent across rebuilds", ctx do
      Sysroot.system_shadow!(ctx.system, [ctx.pkg], ctx.shadow)
      shadow_staging = Sysroot.system_shadow!(ctx.system, [ctx.pkg], ctx.shadow)

      assert File.read!(Path.join(shadow_staging, "usr/lib/libsrtp2.so.1")) == "PACKAGE-LIBSRTP"
      assert File.read!(Path.join(shadow_staging, "usr/lib/libc.so")) == "SYSTEM-LIBC"
    end
  end

  describe "repoint_env!/2" do
    test "rewrites every variable that mentions the real path" do
      real = "/build/system/staging-#{System.unique_integer([:positive])}"
      shadow = "/build/shadow/staging-#{System.unique_integer([:positive])}"

      cflags = "CFLAGS_#{System.unique_integer([:positive])}"
      sysroot = "PKG_CONFIG_SYSROOT_#{System.unique_integer([:positive])}"
      unrelated = "UNRELATED_#{System.unique_integer([:positive])}"

      System.put_env(cflags, "--sysroot=#{real} -O2")
      System.put_env(sysroot, real)
      System.put_env(unrelated, "/usr/bin")

      on_exit(fn -> Enum.each([cflags, sysroot, unrelated], &System.delete_env/1) end)

      Sysroot.repoint_env!(real, shadow)

      assert System.get_env(cflags) == "--sysroot=#{shadow} -O2"
      assert System.get_env(sysroot) == shadow
      assert System.get_env(unrelated) == "/usr/bin"
    end
  end
end
