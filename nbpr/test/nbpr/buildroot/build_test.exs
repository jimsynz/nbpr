defmodule NBPR.Buildroot.BuildTest do
  use ExUnit.Case, async: false

  alias NBPR.Buildroot.Build

  describe "make_args/2" do
    test "prepends `O=<dir>` to the target list" do
      assert Build.make_args("/tmp/out", ["olddefconfig"]) == ["O=/tmp/out", "olddefconfig"]

      assert Build.make_args("/tmp/out", ["jq-rebuild"]) == ["O=/tmp/out", "jq-rebuild"]
    end
  end

  describe "build_env/0" do
    test "exposes the shared BR download cache via BR2_DL_DIR" do
      env = Build.build_env()

      assert {"BR2_DL_DIR", path} = List.keyfind(env, "BR2_DL_DIR", 0)
      assert String.contains?(path, "buildroot-dl")
    end
  end

  describe "build!/3" do
    @tag :linux_only
    test "raises on non-Linux hosts with a clear message" do
      case :os.type() do
        {:unix, :linux} ->
          # Skip — this test only meaningful on non-Linux
          :ok

        _ ->
          assert_raise RuntimeError, ~r/requires a Linux host/, fn ->
            Build.build!("/nonexistent", "BR2_arm=y\n", "jq")
          end
      end
    end
  end
end
