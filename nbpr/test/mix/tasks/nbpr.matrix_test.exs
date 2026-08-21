defmodule Mix.Tasks.Nbpr.MatrixTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Nbpr.Matrix

  @targets ~w(rpi4 bbb x86_64)

  describe "module_for/1" do
    test "strips the `nbpr_` prefix and camelizes the remainder" do
      assert Matrix.module_for("nbpr_jq") == "NBPR.Jq"
      assert Matrix.module_for("nbpr_dnsmasq") == "NBPR.Dnsmasq"
    end

    test "preserves underscores via standard camelize semantics" do
      assert Matrix.module_for("nbpr_some_thing") == "NBPR.SomeThing"
    end
  end

  describe "select/4" do
    test "a changed package builds on every target" do
      selected = Matrix.select(entries(), ["packages/nbpr_flac/mix.exs"], [], "rpi4")

      assert Enum.map(selected, & &1.target) |> Enum.sort() == Enum.sort(@targets)
      assert Enum.uniq(Enum.map(selected, & &1.package)) == ["nbpr_flac"]
    end

    test "several files in one package still build it once per target" do
      selected =
        Matrix.select(
          entries(),
          ["packages/nbpr_flac/mix.exs", "packages/nbpr_flac/lib/nbpr/flac.ex"],
          [],
          "rpi4"
        )

      assert length(selected) == length(@targets)
    end

    test "a changed system pin rebuilds every package, only on that target" do
      selected = Matrix.select(entries(), ["mix.exs"], ["bbb"], "rpi4")

      assert Enum.uniq(Enum.map(selected, & &1.target)) == ["bbb"]
      assert Enum.map(selected, & &1.package) |> Enum.sort() == ["nbpr_flac", "nbpr_jq"]
    end

    test "a library change takes smoke coverage on the default target only" do
      selected = Matrix.select(entries(), ["nbpr/lib/nbpr/buildroot/defconfig.ex"], [], "rpi4")

      assert Enum.uniq(Enum.map(selected, & &1.target)) == ["rpi4"]
      assert Enum.map(selected, & &1.package) |> Enum.sort() == ["nbpr_flac", "nbpr_jq"]
    end

    test "the build workflow itself earns the same smoke coverage" do
      selected = Matrix.select(entries(), [".github/workflows/build.yml"], [], "bbb")

      assert Enum.uniq(Enum.map(selected, & &1.target)) == ["bbb"]
    end

    test "docs and unrelated workflows build nothing" do
      paths = [
        "README.md",
        "docs/howto/add-a-buildroot-package.md",
        ".github/workflows/test.yml",
        "renovate.json"
      ]

      assert Matrix.select(entries(), paths, [], "rpi4") == []
    end

    test "a package qualifying twice over is not built twice" do
      selected =
        Matrix.select(
          entries(),
          ["packages/nbpr_flac/mix.exs", "nbpr/lib/nbpr.ex"],
          ["rpi4"],
          "rpi4"
        )

      assert length(Enum.uniq(selected)) == length(selected)
      assert Enum.count(selected, &(&1.package == "nbpr_flac" and &1.target == "rpi4")) == 1
    end

    test "a path under packages/ that isn't an nbpr package is ignored" do
      assert Matrix.select(entries(), ["packages/README.md"], [], "rpi4") == []
    end
  end

  describe "changed_targets/2" do
    test "reports only the targets whose pinned version moved" do
      previous = mix_exs(%{"rpi4" => "2.1.0", "bbb" => "2.30.1"})
      current = mix_exs(%{"rpi4" => "2.1.1", "bbb" => "2.30.1"})

      assert Matrix.changed_targets(previous, current) == ["rpi4"]
    end

    test "a newly added target counts as changed" do
      previous = mix_exs(%{"rpi4" => "2.1.1"})
      current = mix_exs(%{"rpi4" => "2.1.1", "trellis" => "0.4.2"})

      assert Matrix.changed_targets(previous, current) == ["trellis"]
    end

    test "an unrelated edit to mix.exs moves nothing" do
      pins = %{"rpi4" => "2.1.1", "bbb" => "2.30.1"}

      assert Matrix.changed_targets(mix_exs(pins), mix_exs(pins) <> "\n# a comment\n") == []
    end

    test "a removed target is not reported — it has no entries to build" do
      previous = mix_exs(%{"rpi4" => "2.1.1", "bbb" => "2.30.1"})
      current = mix_exs(%{"rpi4" => "2.1.1"})

      assert Matrix.changed_targets(previous, current) == []
    end
  end

  defp entries do
    for package <- ["nbpr_flac", "nbpr_jq"], target <- @targets do
      %{
        package: package,
        module: Matrix.module_for(package),
        target: target,
        system_version: "1.0.0"
      }
    end
  end

  defp mix_exs(pins) do
    body =
      Enum.map_join(pins, ",\n", fn {target, version} ->
        ~s|    #{target}: {"nerves-project/nerves_system_#{target}", "#{version}"}|
      end)

    "  @prebuild_systems %{\n" <> body <> "\n  }\n"
  end
end
