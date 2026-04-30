defmodule NBPR.Buildroot.FilesListTest do
  use ExUnit.Case, async: true

  alias NBPR.Buildroot.FilesList

  setup do
    tmp = Path.join(System.tmp_dir!(), "nbpr_files_list_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "copy!/3" do
    test "copies regular files listed in the files-list", %{tmp: tmp} do
      src = Path.join(tmp, "src")
      dst = Path.join(tmp, "dst")
      list = Path.join(tmp, "files-list.txt")

      File.mkdir_p!(Path.join(src, "usr/bin"))
      File.mkdir_p!(Path.join(src, "usr/lib"))
      File.write!(Path.join(src, "usr/bin/jq"), "binary")
      File.write!(Path.join(src, "usr/lib/libjq.so.1.0.4"), "lib")

      File.write!(list, """
      jq,./usr/bin/jq
      jq,./usr/lib/libjq.so.1.0.4
      """)

      :ok = FilesList.copy!(src, dst, list)

      assert File.read!(Path.join(dst, "usr/bin/jq")) == "binary"
      assert File.read!(Path.join(dst, "usr/lib/libjq.so.1.0.4")) == "lib"
    end

    test "preserves symlinks as symlinks", %{tmp: tmp} do
      src = Path.join(tmp, "src")
      dst = Path.join(tmp, "dst")
      list = Path.join(tmp, "files-list.txt")

      File.mkdir_p!(Path.join(src, "usr/lib"))
      File.write!(Path.join(src, "usr/lib/libjq.so.1.0.4"), "lib")
      File.ln_s!("libjq.so.1.0.4", Path.join(src, "usr/lib/libjq.so.1"))

      File.write!(list, """
      jq,./usr/lib/libjq.so.1.0.4
      jq,./usr/lib/libjq.so.1
      """)

      :ok = FilesList.copy!(src, dst, list)

      assert {:ok, "libjq.so.1.0.4"} = File.read_link(Path.join(dst, "usr/lib/libjq.so.1"))
      assert File.read!(Path.join(dst, "usr/lib/libjq.so.1.0.4")) == "lib"
    end

    test "drops dev/docs paths", %{tmp: tmp} do
      src = Path.join(tmp, "src")
      dst = Path.join(tmp, "dst")
      list = Path.join(tmp, "files-list.txt")

      for path <- [
            "usr/include/jq.h",
            "usr/lib/pkgconfig/libjq.pc",
            "usr/share/doc/jq/README.md",
            "usr/share/man/man1/jq.1",
            "usr/share/info/jq.info",
            "usr/lib/libjq.la",
            "usr/bin/jq"
          ] do
        File.mkdir_p!(Path.join(src, Path.dirname(path)))
        File.write!(Path.join(src, path), "x")
      end

      File.write!(list, """
      jq,./usr/include/jq.h
      jq,./usr/lib/pkgconfig/libjq.pc
      jq,./usr/share/doc/jq/README.md
      jq,./usr/share/man/man1/jq.1
      jq,./usr/share/info/jq.info
      jq,./usr/lib/libjq.la
      jq,./usr/bin/jq
      """)

      :ok = FilesList.copy!(src, dst, list)

      assert File.exists?(Path.join(dst, "usr/bin/jq"))
      refute File.exists?(Path.join(dst, "usr/include/jq.h"))
      refute File.exists?(Path.join(dst, "usr/lib/pkgconfig/libjq.pc"))
      refute File.exists?(Path.join(dst, "usr/share/doc/jq/README.md"))
      refute File.exists?(Path.join(dst, "usr/share/man/man1/jq.1"))
      refute File.exists?(Path.join(dst, "usr/share/info/jq.info"))
      refute File.exists?(Path.join(dst, "usr/lib/libjq.la"))
    end

    test "silently skips listed files that don't exist on disk", %{tmp: tmp} do
      src = Path.join(tmp, "src")
      dst = Path.join(tmp, "dst")
      list = Path.join(tmp, "files-list.txt")

      File.mkdir_p!(Path.join(src, "usr/bin"))
      File.write!(Path.join(src, "usr/bin/jq"), "binary")

      File.write!(list, """
      jq,./usr/bin/jq
      jq,./usr/bin/missing
      """)

      :ok = FilesList.copy!(src, dst, list)

      assert File.exists?(Path.join(dst, "usr/bin/jq"))
      refute File.exists?(Path.join(dst, "usr/bin/missing"))
    end

    test "no-op when files-list does not exist", %{tmp: tmp} do
      src = Path.join(tmp, "src")
      dst = Path.join(tmp, "dst")
      list = Path.join(tmp, "absent.txt")

      File.mkdir_p!(src)

      assert :ok = FilesList.copy!(src, dst, list)
      refute File.exists?(dst)
    end

    test "ignores blank and malformed lines", %{tmp: tmp} do
      src = Path.join(tmp, "src")
      dst = Path.join(tmp, "dst")
      list = Path.join(tmp, "files-list.txt")

      File.mkdir_p!(Path.join(src, "usr/bin"))
      File.write!(Path.join(src, "usr/bin/jq"), "binary")

      File.write!(list, """

      malformed-no-comma

      jq,./usr/bin/jq
      """)

      :ok = FilesList.copy!(src, dst, list)

      assert File.exists?(Path.join(dst, "usr/bin/jq"))
    end
  end
end
