defmodule NBPRTest do
  use ExUnit.Case, async: true

  doctest NBPR

  @moduletag :tmp_dir

  describe "lib_dirs_env/1" do
    test "returns no env when no candidate dirs contain libraries", %{tmp_dir: tmp_dir} do
      assert NBPR.lib_dirs_env([tmp_dir]) == []
    end

    test "joins existing usr/lib and lib dirs into a single LD_LIBRARY_PATH", %{tmp_dir: tmp_dir} do
      priv_a = Path.join(tmp_dir, "a")
      priv_b = Path.join(tmp_dir, "b")
      File.mkdir_p!(Path.join(priv_a, "usr/lib"))
      File.mkdir_p!(Path.join(priv_b, "lib"))

      assert [{"LD_LIBRARY_PATH", path}] = NBPR.lib_dirs_env([priv_a, priv_b])

      assert path ==
               Enum.join([Path.join(priv_a, "usr/lib"), Path.join(priv_b, "lib")], ":")
    end

    test "includes both usr/lib and lib from a single priv when both exist", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "usr/lib"))
      File.mkdir_p!(Path.join(tmp_dir, "lib"))

      assert [{"LD_LIBRARY_PATH", path}] = NBPR.lib_dirs_env([tmp_dir])

      assert path ==
               Enum.join([Path.join(tmp_dir, "usr/lib"), Path.join(tmp_dir, "lib")], ":")
    end
  end

  describe "cmd_env/1" do
    test "raises for a module that isn't an NBPR package" do
      assert_raise ArgumentError, ~r/is not an NBPR package/, fn ->
        NBPR.cmd_env(Enum)
      end
    end
  end

  describe "run/4" do
    test "raises for a module that isn't an NBPR package" do
      assert_raise ArgumentError, ~r/is not an NBPR package/, fn ->
        NBPR.run(Enum, "bin/whatever", [])
      end
    end
  end
end
