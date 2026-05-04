defmodule Mix.Tasks.Nbpr.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  describe "firmware alias merging" do
    test "creates an aliases keyword with the firmware entry when none exists" do
      mix_exs =
        test_project(files: %{"mix.exs" => mix_exs_with(nil)})
        |> Igniter.compose_task("nbpr.install", [])
        |> apply_igniter!()
        |> source_for("mix.exs")

      assert mix_exs =~ ~s|aliases: [firmware: ["nbpr.fetch", "firmware"]]|
    end

    test "adds the firmware entry when aliases exists without it" do
      mix_exs =
        test_project(files: %{"mix.exs" => mix_exs_with(~s|test: ["test"]|)})
        |> Igniter.compose_task("nbpr.install", [])
        |> apply_igniter!()
        |> source_for("mix.exs")

      assert mix_exs =~ ~s|test: ["test"]|
      assert mix_exs =~ ~s|firmware: ["nbpr.fetch", "firmware"]|
    end

    test "prepends `nbpr.fetch` to an existing firmware alias" do
      mix_exs =
        test_project(
          files: %{"mix.exs" => mix_exs_with(~s|firmware: ["custom_step", "firmware"]|)}
        )
        |> Igniter.compose_task("nbpr.install", [])
        |> apply_igniter!()
        |> source_for("mix.exs")

      assert mix_exs =~ ~s|firmware: ["nbpr.fetch", "custom_step", "firmware"]|
    end

    test "is idempotent when nbpr.fetch is already present in the firmware alias" do
      test_project(files: %{"mix.exs" => mix_exs_with(~s|firmware: ["nbpr.fetch", "firmware"]|)})
      |> Igniter.compose_task("nbpr.install", [])
      |> assert_unchanged("mix.exs")
    end
  end

  describe "post-install tasks" do
    test "queues `mix hex.organization auth nbpr` with the public read key" do
      igniter =
        test_project()
        |> Igniter.compose_task("nbpr.install", [])

      assert Enum.any?(igniter.tasks, fn
               {"hex.organization", ["auth", "nbpr", "--key", _key]} -> true
               _ -> false
             end)
    end
  end

  defp mix_exs_with(nil) do
    """
    defmodule Test.MixProject do
      use Mix.Project

      def project do
        [
          app: :test,
          version: "0.1.0",
          deps: deps()
        ]
      end

      defp deps, do: []
    end
    """
  end

  defp mix_exs_with(aliases_entry) when is_binary(aliases_entry) do
    """
    defmodule Test.MixProject do
      use Mix.Project

      def project do
        [
          app: :test,
          version: "0.1.0",
          aliases: [#{aliases_entry}],
          deps: deps()
        ]
      end

      defp deps, do: []
    end
    """
  end

  defp source_for(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end
end
