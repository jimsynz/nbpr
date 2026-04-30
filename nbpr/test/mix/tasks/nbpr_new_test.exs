defmodule Mix.Tasks.Nbpr.NewTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "nbpr_new_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    File.write!(Path.join(tmp, "PLAN.md"), "# fixture workspace\n")
    File.mkdir_p!(Path.join(tmp, "nbpr"))

    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, tmp: tmp}
  end

  describe "run/1 with a valid name" do
    test "creates the expected file tree", %{tmp: tmp} do
      capture_io(fn ->
        File.cd!(tmp, fn -> Mix.Tasks.Nbpr.New.run(["containerd"]) end)
      end)

      base = Path.join(tmp, "packages/nbpr_containerd")
      assert File.exists?(Path.join(base, ".formatter.exs"))
      assert File.exists?(Path.join(base, ".gitignore"))
      assert File.exists?(Path.join(base, "README.md"))
      assert File.exists?(Path.join(base, "mix.exs"))
      assert File.exists?(Path.join(base, "lib/nbpr/containerd.ex"))
      assert File.exists?(Path.join(base, "test/test_helper.exs"))
      assert File.exists?(Path.join(base, "test/nbpr/containerd_test.exs"))
    end

    test "package module file uses NBPR.<Camel> directly", %{tmp: tmp} do
      capture_io(fn ->
        File.cd!(tmp, fn -> Mix.Tasks.Nbpr.New.run(["containerd"]) end)
      end)

      contents = File.read!(Path.join(tmp, "packages/nbpr_containerd/lib/nbpr/containerd.ex"))

      assert contents =~ "defmodule NBPR.Containerd do"
      assert contents =~ "use NBPR.BrPackage"
      assert contents =~ ~s|br_package: "containerd"|
      assert contents =~ "artifact_sites: []"
    end

    test "mix.exs declares the right app and depends on :nbpr", %{tmp: tmp} do
      capture_io(fn ->
        File.cd!(tmp, fn -> Mix.Tasks.Nbpr.New.run(["containerd"]) end)
      end)

      contents = File.read!(Path.join(tmp, "packages/nbpr_containerd/mix.exs"))

      assert contents =~ "app: :nbpr_containerd"
      assert contents =~ ~s|{:nbpr, "~> 0.1"}|
    end
  end

  describe "run/1 with an invalid name" do
    test "rejects uppercase letters" do
      assert_raise Mix.Error, ~r/invalid package name/, fn ->
        Mix.Tasks.Nbpr.New.run(["Foo"])
      end
    end

    test "rejects whitespace" do
      assert_raise Mix.Error, ~r/invalid package name/, fn ->
        Mix.Tasks.Nbpr.New.run(["foo bar"])
      end
    end

    test "rejects leading digit" do
      assert_raise Mix.Error, ~r/invalid package name/, fn ->
        Mix.Tasks.Nbpr.New.run(["1foo"])
      end
    end

    test "rejects leading underscore" do
      assert_raise Mix.Error, ~r/invalid package name/, fn ->
        Mix.Tasks.Nbpr.New.run(["_foo"])
      end
    end

    test "rejects a name that already includes the `nbpr_` prefix" do
      assert_raise Mix.Error, ~r/already starts with `nbpr_`.*use "jq" instead/s, fn ->
        Mix.Tasks.Nbpr.New.run(["nbpr_jq"])
      end
    end
  end

  describe "run/1 when target exists" do
    test "refuses to overwrite", %{tmp: tmp} do
      File.cd!(tmp, fn ->
        File.mkdir_p!("packages/nbpr_already_there")

        assert_raise Mix.Error, ~r/already exists/, fn ->
          Mix.Tasks.Nbpr.New.run(["already_there"])
        end
      end)
    end
  end

  describe "workspace-root detection" do
    test "finds the workspace root when run from a subdirectory", %{tmp: tmp} do
      subdir = Path.join(tmp, "nbpr")

      capture_io(fn ->
        File.cd!(subdir, fn -> Mix.Tasks.Nbpr.New.run(["nested"]) end)
      end)

      assert File.exists?(Path.join(tmp, "packages/nbpr_nested/mix.exs"))
      refute File.exists?(Path.join(subdir, "packages/nbpr_nested/mix.exs"))
    end

    test "raises when not in a workspace tree" do
      not_a_workspace =
        Path.join(System.tmp_dir!(), "nbpr_no_workspace_#{System.unique_integer([:positive])}")

      File.mkdir_p!(not_a_workspace)
      on_exit(fn -> File.rm_rf!(not_a_workspace) end)

      File.cd!(not_a_workspace, fn ->
        assert_raise Mix.Error, ~r/Could not locate nbpr workspace root/, fn ->
          Mix.Tasks.Nbpr.New.run(["foo"])
        end
      end)
    end
  end

  describe "run/1 with no args" do
    test "prints usage" do
      assert_raise Mix.Error, ~r/usage:/, fn ->
        Mix.Tasks.Nbpr.New.run([])
      end
    end
  end
end
