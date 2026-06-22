defmodule NBPR.Linux.ConfigTest do
  use ExUnit.Case, async: true

  alias NBPR.Linux.Config

  setup do
    root = Path.join(System.tmp_dir!(), "nbpr_linux_cfg_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "config/linux"))
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  defp write(root, rel, contents) do
    path = Path.join(root, rel)
    File.write!(path, contents)
    path
  end

  describe "resolve/2" do
    test "expands fragment/patch paths relative to the project root", %{root: root} do
      write(root, "config/linux/a.fragment", "CONFIG_FOO=y\n")
      write(root, "config/linux/0001.patch", "--- patch\n")

      Application.put_env(:nbpr_linux_test, :config_fragments, ["config/linux/a.fragment"])
      Application.put_env(:nbpr_linux_test, :patches, ["config/linux/0001.patch"])
      on_exit(fn -> Application.delete_env(:nbpr_linux_test, :config_fragments) end)
      on_exit(fn -> Application.delete_env(:nbpr_linux_test, :patches) end)

      resolved = Config.resolve(:nbpr_linux_test, root)

      assert resolved.fragments == [Path.join(root, "config/linux/a.fragment")]
      assert resolved.patches == [Path.join(root, "config/linux/0001.patch")]
    end

    test "defaults to empty when nothing is configured", %{root: root} do
      assert Config.resolve(:nbpr_linux_unset, root) == %{fragments: [], patches: []}
    end

    test "raises with a clear message for a missing file", %{root: root} do
      Application.put_env(:nbpr_linux_missing, :config_fragments, ["config/linux/nope.fragment"])
      on_exit(fn -> Application.delete_env(:nbpr_linux_missing, :config_fragments) end)

      assert_raise ArgumentError, ~r/fragment not found.*nope\.fragment/, fn ->
        Config.resolve(:nbpr_linux_missing, root)
      end
    end
  end

  describe "digest/1" do
    test "is stable under reordering", %{root: root} do
      a = write(root, "config/linux/a.fragment", "CONFIG_A=y\n")
      b = write(root, "config/linux/b.fragment", "CONFIG_B=y\n")

      assert Config.digest(%{fragments: [a, b], patches: []}) ==
               Config.digest(%{fragments: [b, a], patches: []})
    end

    test "changes when a file's contents change", %{root: root} do
      a = write(root, "config/linux/a.fragment", "CONFIG_A=y\n")
      before = Config.digest(%{fragments: [a], patches: []})

      File.write!(a, "CONFIG_A=m\n")
      assert Config.digest(%{fragments: [a], patches: []}) != before
    end

    test "empty config yields a stable non-empty digest" do
      assert is_binary(Config.digest(%{fragments: [], patches: []}))
    end
  end
end
