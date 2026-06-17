defmodule NBPR.Artifact.LibCheckTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  alias NBPR.Artifact.LibCheck

  describe "provided_sonames/1" do
    test "collects soname filenames across existing dirs, ignoring non-libs", %{tmp_dir: tmp_dir} do
      a = Path.join(tmp_dir, "a")
      b = Path.join(tmp_dir, "b")
      File.mkdir_p!(a)
      File.mkdir_p!(b)
      File.write!(Path.join(a, "libpopt.so.0"), "")
      File.write!(Path.join(a, "README"), "")
      File.write!(Path.join(b, "libc.so.6"), "")

      provided = LibCheck.provided_sonames([a, b, Path.join(tmp_dir, "absent")])

      assert MapSet.member?(provided, "libpopt.so.0")
      assert MapSet.member?(provided, "libc.so.6")
      refute MapSet.member?(provided, "README")
    end
  end

  describe "unresolved/2" do
    test "returns per-package missing sonames, sorted and deduped" do
      provided = MapSet.new(["libc.so.6", "libpopt.so.0"])

      required = [
        {:nbpr_cryptsetup,
         ["libc.so.6", "libdevmapper.so.1.02", "libpopt.so.0", "libjson-c.so.5"]},
        {:nbpr_jq, ["libc.so.6"]},
        {:nbpr_dup, ["libfoo.so.1", "libfoo.so.1"]}
      ]

      assert LibCheck.unresolved(required, provided) == [
               {:nbpr_cryptsetup, ["libdevmapper.so.1.02", "libjson-c.so.5"]},
               {:nbpr_dup, ["libfoo.so.1"]}
             ]
    end

    test "a soname provided by a sibling package is not reported missing" do
      provided = MapSet.new(["libc.so.6", "libblkid.so.1"])
      required = [{:nbpr_e2fsprogs, ["libblkid.so.1", "libc.so.6"]}]

      assert LibCheck.unresolved(required, provided) == []
    end
  end

  describe "base_lib_dirs/1" do
    test "returns [] for nil" do
      assert LibCheck.base_lib_dirs(nil) == []
    end

    test "returns existing staging lib dirs under the system path", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join([tmp_dir, "staging", "lib"]))
      File.mkdir_p!(Path.join([tmp_dir, "staging", "usr", "lib"]))

      assert LibCheck.base_lib_dirs(tmp_dir) == [
               Path.join([tmp_dir, "staging", "lib"]),
               Path.join([tmp_dir, "staging", "usr", "lib"])
             ]
    end
  end

  describe "missing/2" do
    test "returns [] when no packages are staged" do
      assert LibCheck.missing([], []) == []
    end

    test "ignores non-ELF files in a package's priv", %{tmp_dir: tmp_dir} do
      priv = Path.join(tmp_dir, "priv")
      File.mkdir_p!(Path.join(priv, "usr/bin"))
      File.write!(Path.join(priv, "usr/bin/config.txt"), "not an elf")

      assert LibCheck.missing([], [{:nbpr_thing, priv}]) == []
    end
  end
end
