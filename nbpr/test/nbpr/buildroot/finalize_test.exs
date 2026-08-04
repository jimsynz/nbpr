defmodule NBPR.Buildroot.FinalizeTest do
  use ExUnit.Case, async: true

  alias NBPR.Buildroot.Finalize

  # Every test runs the emitted fragment through a real `sh`, because the whole
  # module is a shell-script generator — asserting on the string would test the
  # template, not the behaviour.
  setup do
    root = Path.join(System.tmp_dir!(), "nbpr_finalize_#{System.unique_integer([:positive])}")
    target = Path.join(root, "target")
    host_bin = Path.join(root, "host/bin")
    config = Path.join(root, ".config")

    File.mkdir_p!(host_bin)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root, target: target, host_bin: host_bin, config: config}
  end

  defp write!(target, rel, contents \\ "x") do
    path = Path.join(target, rel)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    path
  end

  # Prefer dash: the shell backend invokes plain `sh`, which on Debian and
  # Ubuntu (including CI) is dash, and it's the stricter of the two shells the
  # fragment has to survive — the container backend runs it under bash. `-e` so
  # an unexpected failure surfaces instead of being swallowed; deliberately no
  # `pipefail`, which dash doesn't have and Buildroot's own recipe doesn't use.
  defp shell do
    System.find_executable("dash") || System.find_executable("sh") || "sh"
  end

  defp run!(ctx, config_lines) do
    File.write!(ctx.config, Enum.join(config_lines, "\n") <> "\n")
    script = Finalize.script(ctx.target, ctx.host_bin, ctx.config)

    {output, status} = System.cmd(shell(), ["-e", "-c", script], stderr_to_stdout: true)

    assert status == 0, "finalize script failed:\n#{output}"
    output
  end

  defp exists?(target, rel), do: File.exists?(Path.join(target, rel))

  describe "file removals" do
    test "drops the dev and docs paths target-finalize drops", ctx do
      for rel <- [
            "usr/include/foo.h",
            "usr/share/aclocal/foo.m4",
            "usr/lib/pkgconfig/foo.pc",
            "usr/share/pkgconfig/foo.pc",
            "usr/lib/cmake/Foo.cmake",
            "usr/lib/rpm/macros",
            "usr/share/man/man1/foo.1",
            "usr/share/info/foo.info",
            "usr/share/doc/foo/README",
            "usr/share/gtk-doc/html/index.html"
          ],
          do: write!(ctx.target, rel)

      run!(ctx, ["BR2_STRIP_strip=y"])

      refute exists?(ctx.target, "usr/include")
      refute exists?(ctx.target, "usr/share/aclocal")
      refute exists?(ctx.target, "usr/lib/pkgconfig")
      refute exists?(ctx.target, "usr/share/pkgconfig")
      refute exists?(ctx.target, "usr/lib/cmake")
      refute exists?(ctx.target, "usr/lib/rpm")
      refute exists?(ctx.target, "usr/share/man")
      refute exists?(ctx.target, "usr/share/info")
      refute exists?(ctx.target, "usr/share/doc")
      refute exists?(ctx.target, "usr/share/gtk-doc")
    end

    test "drops static archives, libtool archives and .prl files", ctx do
      write!(ctx.target, "usr/lib/libfoo.a")
      write!(ctx.target, "usr/lib/libfoo.la")
      write!(ctx.target, "usr/lib/libfoo.prl")
      write!(ctx.target, "lib/libbar.a")
      write!(ctx.target, "usr/libexec/libbaz.a")
      keep = write!(ctx.target, "usr/lib/libfoo.so.1")

      run!(ctx, ["BR2_STRIP_strip=y"])

      refute exists?(ctx.target, "usr/lib/libfoo.a")
      refute exists?(ctx.target, "usr/lib/libfoo.la")
      refute exists?(ctx.target, "usr/lib/libfoo.prl")
      refute exists?(ctx.target, "lib/libbar.a")
      refute exists?(ctx.target, "usr/libexec/libbaz.a")
      assert File.exists?(keep), "shared libraries must survive"
    end

    test "keeps a package's own bash completions when bash is in the firmware", ctx do
      write!(ctx.target, "usr/share/bash-completion/completions/foo")

      run!(ctx, ["BR2_STRIP_strip=y", "BR2_PACKAGE_BASH=y"])

      assert exists?(ctx.target, "usr/share/bash-completion/completions/foo")
    end

    test "drops bash completions when bash isn't", ctx do
      write!(ctx.target, "usr/share/bash-completion/completions/foo")

      run!(ctx, ["BR2_STRIP_strip=y"])

      refute exists?(ctx.target, "usr/share/bash-completion")
    end

    test "keeps split debug info only when debugging is on and stripping off", ctx do
      write!(ctx.target, "usr/lib/debug/libfoo.debug")
      run!(ctx, ["BR2_ENABLE_DEBUG=y"])
      assert exists?(ctx.target, "usr/lib/debug/libfoo.debug")

      write!(ctx.target, "usr/lib/debug/libfoo.debug")
      run!(ctx, ["BR2_ENABLE_DEBUG=y", "BR2_STRIP_strip=y"])
      refute exists?(ctx.target, "usr/lib/debug")
    end

    test "leaves an otherwise-populated usr/share in place", ctx do
      write!(ctx.target, "usr/share/gpsd/gpsd.png")
      write!(ctx.target, "usr/share/man/man8/gpsd.8")

      run!(ctx, ["BR2_STRIP_strip=y"])

      refute exists?(ctx.target, "usr/share/man")
      assert exists?(ctx.target, "usr/share/gpsd/gpsd.png")
    end

    test "is a no-op on a tree with nothing to remove", ctx do
      write!(ctx.target, "usr/sbin/gpsd")

      run!(ctx, ["BR2_STRIP_strip=y"])

      assert exists?(ctx.target, "usr/sbin/gpsd")
    end
  end

  describe "stripping" do
    # A stub `*-strip` that records its arguments, so the tests can assert on
    # which files Buildroot's find clauses select without needing a real
    # cross-toolchain or ELF binaries.
    defp stub_strip!(ctx) do
      log = Path.join(ctx.root, "strip.log")
      path = Path.join(ctx.host_bin, "aarch64-nerves-linux-gnu-strip")

      File.write!(path, """
      #!/bin/sh
      for a in "$@"; do echo "$a" >> #{log}; done
      """)

      File.chmod!(path, 0o755)
      log
    end

    defp stripped(log) do
      case File.read(log) do
        {:ok, contents} -> contents |> String.split("\n", trim: true) |> Enum.sort()
        {:error, :enoent} -> []
      end
    end

    test "strips executables and shared libraries", ctx do
      log = stub_strip!(ctx)
      bin = write!(ctx.target, "usr/sbin/chronyd")
      File.chmod!(bin, 0o755)
      write!(ctx.target, "usr/lib/libcap.so.2")
      write!(ctx.target, "etc/chrony.conf")

      run!(ctx, ["BR2_STRIP_strip=y"])
      args = stripped(log)

      assert Path.join(ctx.target, "usr/sbin/chronyd") in args
      assert Path.join(ctx.target, "usr/lib/libcap.so.2") in args
      refute Path.join(ctx.target, "etc/chrony.conf") in args
    end

    test "never fully strips kernel modules, ld.so or libpthread", ctx do
      log = stub_strip!(ctx)

      for rel <- ["lib/modules/6.1/zfs.ko", "lib/ld-linux-aarch64.so.1", "lib/libpthread.so.0"] do
        path = write!(ctx.target, rel)
        File.chmod!(path, 0o755)
      end

      run!(ctx, ["BR2_STRIP_strip=y"])
      args = stripped(log)

      refute Path.join(ctx.target, "lib/modules/6.1/zfs.ko") in args,
             "stripping a .ko breaks it"

      # ld.so and libpthread appear, but only via the --strip-debug pass.
      assert "--strip-debug" in args
      assert Path.join(ctx.target, "lib/ld-linux-aarch64.so.1") in args
      assert Path.join(ctx.target, "lib/libpthread.so.0") in args
    end

    test "passes Buildroot's STRIPCMD flags", ctx do
      log = stub_strip!(ctx)
      bin = write!(ctx.target, "usr/bin/foo")
      File.chmod!(bin, 0o755)

      run!(ctx, ["BR2_STRIP_strip=y"])
      args = stripped(log)

      assert "--remove-section=.comment" in args
      assert "--remove-section=.note" in args
    end

    test "skips stripping when BR2_STRIP_strip is unset", ctx do
      log = stub_strip!(ctx)
      bin = write!(ctx.target, "usr/bin/foo")
      File.chmod!(bin, 0o755)

      output = run!(ctx, ["BR2_ENABLE_DEBUG=y"])

      assert stripped(log) == []
      assert output =~ "BR2_STRIP_strip is not set"
    end

    test "skips stripping, loudly, when the system sets strip exclusions", ctx do
      log = stub_strip!(ctx)
      bin = write!(ctx.target, "usr/bin/foo")
      File.chmod!(bin, 0o755)

      output = run!(ctx, ["BR2_STRIP_strip=y", ~s(BR2_STRIP_EXCLUDE_DIRS="/usr/lib/firmware")])

      assert stripped(log) == []
      assert output =~ "BR2_STRIP_EXCLUDE"
    end

    test "an empty exclusion setting doesn't count as set", ctx do
      log = stub_strip!(ctx)
      bin = write!(ctx.target, "usr/bin/foo")
      File.chmod!(bin, 0o755)

      run!(ctx, [
        "BR2_STRIP_strip=y",
        ~s(BR2_STRIP_EXCLUDE_DIRS=""),
        ~s(BR2_STRIP_EXCLUDE_FILES="")
      ])

      assert Path.join(ctx.target, "usr/bin/foo") in stripped(log)
    end

    test "warns rather than failing when no cross strip is present", ctx do
      bin = write!(ctx.target, "usr/bin/foo")
      File.chmod!(bin, 0o755)

      output = run!(ctx, ["BR2_STRIP_strip=y"])

      assert output =~ "no cross strip"
      assert File.exists?(bin)
    end
  end

  describe "config reading" do
    test "a missing config skips stripping instead of crashing", ctx do
      stub_strip!(ctx)
      bin = write!(ctx.target, "usr/bin/foo")
      File.chmod!(bin, 0o755)

      script = Finalize.script(ctx.target, ctx.host_bin, Path.join(ctx.root, "absent.config"))
      {output, status} = System.cmd(shell(), ["-e", "-c", script], stderr_to_stdout: true)

      assert status == 0
      assert output =~ "BR2_STRIP_strip is not set"
    end

    test "a commented-out symbol doesn't read as enabled", ctx do
      log = stub_strip!(ctx)
      write!(ctx.target, "usr/share/bash-completion/completions/foo")

      run!(ctx, ["BR2_STRIP_strip=y", "# BR2_PACKAGE_BASH is not set"])

      refute exists?(ctx.target, "usr/share/bash-completion")
      assert stripped(log) == []
    end
  end
end
