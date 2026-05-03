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
        File.cd!(tmp, fn -> Mix.Tasks.Nbpr.New.run(["containerd", "--no-lookup"]) end)
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
        File.cd!(tmp, fn -> Mix.Tasks.Nbpr.New.run(["containerd", "--no-lookup"]) end)
      end)

      contents = File.read!(Path.join(tmp, "packages/nbpr_containerd/lib/nbpr/containerd.ex"))

      assert contents =~ "defmodule NBPR.Containerd do"
      assert contents =~ "use NBPR.BrPackage"
      assert contents =~ ~s|br_package: "containerd"|
      assert contents =~ "artifact_sites: [{:ghcr,"
    end

    test "mix.exs declares the right app and depends on :nbpr", %{tmp: tmp} do
      capture_io(fn ->
        File.cd!(tmp, fn -> Mix.Tasks.Nbpr.New.run(["containerd", "--no-lookup"]) end)
      end)

      contents = File.read!(Path.join(tmp, "packages/nbpr_containerd/mix.exs"))

      assert contents =~ "app: :nbpr_containerd"
      assert contents =~ "{:nbpr, nbpr_dep()}"
      assert contents =~ "NBPR_RELEASE"
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
        File.cd!(subdir, fn -> Mix.Tasks.Nbpr.New.run(["nested", "--no-lookup"]) end)
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

  describe "BR metadata lookup" do
    @br_version "9999.99.99"

    setup do
      tmp =
        Path.join(System.tmp_dir!(), "nbpr_new_lookup_test_#{System.unique_integer([:positive])}")

      artifacts =
        Path.join(System.tmp_dir!(), "nbpr_new_artifacts_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      File.write!(Path.join(tmp, "PLAN.md"), "# fixture\n")
      File.mkdir_p!(Path.join(tmp, "nbpr"))

      seed_nerves_system_br!(tmp, @br_version)
      seed_br_cache!(artifacts, @br_version)
      seed_spdx_cache!(artifacts)

      System.put_env("NERVES_ARTIFACTS_DIR", artifacts)

      on_exit(fn ->
        System.delete_env("NERVES_ARTIFACTS_DIR")
        File.rm_rf!(tmp)
        File.rm_rf!(artifacts)
      end)

      {:ok, tmp: tmp, artifacts: artifacts}
    end

    test "bakes version, licences, description, and homepage into mix.exs", %{tmp: tmp} do
      capture_io(fn ->
        File.cd!(tmp, fn -> Mix.Tasks.Nbpr.New.run(["fixturepkg"]) end)
      end)

      mix_exs = File.read!(Path.join(tmp, "packages/nbpr_fixturepkg/mix.exs"))

      assert mix_exs =~ ~s|@version "1.2.3"|
      assert mix_exs =~ ~s|licenses: ["MIT"]|
      assert mix_exs =~ "Fixturepkg does the thing well."
    end

    test "bakes BR-derived data into the lib module", %{tmp: tmp} do
      capture_io(fn ->
        File.cd!(tmp, fn -> Mix.Tasks.Nbpr.New.run(["fixturepkg"]) end)
      end)

      lib = File.read!(Path.join(tmp, "packages/nbpr_fixturepkg/lib/nbpr/fixturepkg.ex"))

      assert lib =~ ~s|description: "Fixturepkg does the thing well."|
      assert lib =~ ~s|homepage: "https://example.com/fixturepkg"|
    end

    test "raises when BR licence is non-SPDX without --licenses override", %{tmp: tmp} do
      seed_br_cache_pkg!(tmp, "borked", "GPL-2.0+")

      assert_raise Mix.Error, ~r/Buildroot licence\(s\) not in SPDX/, fn ->
        capture_io(fn ->
          File.cd!(tmp, fn -> Mix.Tasks.Nbpr.New.run(["borked"]) end)
        end)
      end
    end

    test "--licenses override skips BR validation", %{tmp: tmp} do
      seed_br_cache_pkg!(tmp, "overridden", "GPL-2.0+")

      capture_io(fn ->
        File.cd!(tmp, fn ->
          Mix.Tasks.Nbpr.New.run(["overridden", "--licenses", "GPL-2.0-or-later"])
        end)
      end)

      mix_exs = File.read!(Path.join(tmp, "packages/nbpr_overridden/mix.exs"))
      assert mix_exs =~ ~s|licenses: ["GPL-2.0-or-later"]|
    end

    test "--br-package maps Hex name to a different BR name", %{tmp: tmp} do
      capture_io(fn ->
        File.cd!(tmp, fn ->
          Mix.Tasks.Nbpr.New.run(["mypkg", "--br-package", "fixturepkg"])
        end)
      end)

      lib = File.read!(Path.join(tmp, "packages/nbpr_mypkg/lib/nbpr/mypkg.ex"))
      assert lib =~ ~s|br_package: "fixturepkg"|
    end

    test "raises with a helpful suggestion when BR package name is wrong", %{tmp: tmp} do
      assert_raise Mix.Error, ~r/no Buildroot package named "wrongname"/, fn ->
        capture_io(fn ->
          File.cd!(tmp, fn -> Mix.Tasks.Nbpr.New.run(["wrongname"]) end)
        end)
      end
    end
  end

  defp seed_nerves_system_br!(workspace, version) do
    nerves_br = Path.join([workspace, "deps", "nerves_system_br"])
    File.mkdir_p!(nerves_br)

    File.write!(Path.join(nerves_br, "create-build.sh"), """
    #!/usr/bin/env bash
    NERVES_BR_VERSION=#{version}
    """)
  end

  defp seed_br_cache!(artifacts, version) do
    cache_dir = Path.join([artifacts, "nbpr", "buildroot", version])
    File.mkdir_p!(Path.join(cache_dir, "package"))
    File.write!(Path.join(cache_dir, ".nbpr-ready"), version <> "\n")

    seed_pkg_in_cache!(cache_dir, "fixturepkg",
      mk: """
      FIXTUREPKG_VERSION = 1.2.3
      FIXTUREPKG_SITE = https://example.com/fixturepkg
      FIXTUREPKG_LICENSE = MIT
      """,
      config_in: """
      config BR2_PACKAGE_FIXTUREPKG
      \tbool "fixturepkg"
      \thelp
      \t  Fixturepkg does the thing well.
      """
    )
  end

  defp seed_br_cache_pkg!(workspace, name, license) do
    artifacts = System.get_env("NERVES_ARTIFACTS_DIR")
    cache_dir = Path.join([artifacts, "nbpr", "buildroot", @br_version])

    upper = name |> String.upcase() |> String.replace("-", "_")

    seed_pkg_in_cache!(cache_dir, name,
      mk: """
      #{upper}_VERSION = 9.9.9
      #{upper}_SITE = https://example.com/#{name}
      #{upper}_LICENSE = #{license}
      """,
      config_in: """
      config BR2_PACKAGE_#{upper}
      \tbool "#{name}"
      \thelp
      \t  #{name} is a fixture.
      """
    )

    _ = workspace
  end

  defp seed_pkg_in_cache!(cache_dir, name, mk: mk, config_in: config_in) do
    pkg_dir = Path.join([cache_dir, "package", name])
    File.mkdir_p!(pkg_dir)
    File.write!(Path.join(pkg_dir, "#{name}.mk"), mk)
    File.write!(Path.join(pkg_dir, "Config.in"), config_in)
  end

  defp seed_spdx_cache!(artifacts) do
    cache = Path.join([artifacts, "nbpr", "spdx_licenses.json"])
    File.mkdir_p!(Path.dirname(cache))

    json =
      :json.encode(%{
        "licenseListVersion" => "fixture",
        "licenses" => [
          %{"licenseId" => "MIT"},
          %{"licenseId" => "BSD-3-Clause"},
          %{"licenseId" => "GPL-2.0-only"},
          %{"licenseId" => "GPL-2.0-or-later"}
        ]
      })
      |> IO.iodata_to_binary()

    File.write!(cache, json)
  end
end
