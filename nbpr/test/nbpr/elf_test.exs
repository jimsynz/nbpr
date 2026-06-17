defmodule NBPR.ElfTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  alias NBPR.Elf

  describe "parse_needed/1" do
    test "extracts each NEEDED soname from readelf -d output" do
      output = """
      Dynamic section at offset 0x1dcc contains 27 entries:
        Tag        Type                         Name/Value
       0x00000001 (NEEDED)                     Shared library: [libpopt.so.0]
       0x00000001 (NEEDED)                     Shared library: [libc.so.6]
       0x0000000e (SONAME)                     Library soname: [libcryptsetup.so.12]
       0x00000001 (NEEDED)                     Shared library: [ld-linux-armhf.so.3]
      """

      assert Elf.parse_needed(output) == ["libpopt.so.0", "libc.so.6", "ld-linux-armhf.so.3"]
    end

    test "returns [] when there are no NEEDED entries" do
      assert Elf.parse_needed("no dynamic section here") == []
    end
  end

  describe "elf?/1" do
    test "true for a file starting with the ELF magic", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "fake.so")
      File.write!(path, <<0x7F, "ELF", 0, 0, 0, 0>>)
      assert Elf.elf?(path)
    end

    test "false for a non-ELF file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "script.sh")
      File.write!(path, "#!/bin/sh\necho hi\n")
      refute Elf.elf?(path)
    end

    test "false for a missing file", %{tmp_dir: tmp_dir} do
      refute Elf.elf?(Path.join(tmp_dir, "nope"))
    end
  end

  describe "needed/1" do
    test "returns [] for a non-ELF file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "notelf")
      File.write!(path, "plain text")
      assert Elf.needed(path) == []
    end
  end
end
