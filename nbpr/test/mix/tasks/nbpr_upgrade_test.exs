defmodule Mix.Tasks.Nbpr.UpgradeTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  describe "0.7.0" do
    test "removes `organization: \"nbpr\"` and keeps the dep's other options" do
      upgrade(deps: ~s|{:nbpr_flac, "~> 1.5", organization: "nbpr", targets: @all_targets}|)
      |> assert_has_patch("mix.exs", """
      - |      {:nbpr_flac, "~> 1.5", organization: "nbpr", targets: @all_targets}
      + |      {:nbpr_flac, "~> 1.5", targets: @all_targets}
      """)
    end

    test "collapses a dep whose only option was the organisation" do
      upgrade(deps: ~s|{:nbpr_jq, "~> 1.8", organization: "nbpr"}|)
      |> assert_has_patch("mix.exs", """
      - |      {:nbpr_jq, "~> 1.8", organization: "nbpr"}
      + |      {:nbpr_jq, "~> 1.8"}
      """)
    end

    test "leaves deps from other organisations alone" do
      upgrade(deps: ~s|{:secret, "~> 1.0", organization: "acme"}|)
      |> assert_unchanged("mix.exs")
    end

    test "unlocks every dep the lock resolved from the organisation" do
      lock = """
      %{
        "nbpr": {:hex, :nbpr, "0.6.0", "aa", [:mix], [], "hexpm", "bb"},
        "nbpr_libogg": {:hex, :nbpr_libogg, "1.3.6", "cc", [:mix], [], "hexpm:nbpr", "dd"},
        "nbpr_jq": {:hex, :nbpr_jq, "1.8.2", "ee", [:mix], [], "hexpm:nbpr", "ff"},
      }
      """

      upgrade(deps: ~s|{:nbpr_jq, "~> 1.8", organization: "nbpr"}|, lock: lock)
      |> assert_has_task("deps.unlock", ["nbpr_jq", "nbpr_libogg"])
    end

    test "doesn't run before 0.7.0" do
      upgrade(deps: ~s|{:nbpr_jq, "~> 1.8", organization: "nbpr"}|, from: "0.5.0", to: "0.6.0")
      |> assert_unchanged("mix.exs")
    end
  end

  defp upgrade(opts) do
    files =
      %{"mix.exs" => mix_exs(opts[:deps])}
      |> then(fn files ->
        if lock = opts[:lock], do: Map.put(files, "mix.lock", lock), else: files
      end)

    test_project(files: files)
    |> Igniter.compose_task("nbpr.upgrade", [opts[:from] || "0.6.0", opts[:to] || "0.7.0"])
  end

  defp mix_exs(dep) do
    """
    defmodule Test.MixProject do
      use Mix.Project

      @all_targets [:rpi4]

      def project do
        [
          app: :test,
          version: "0.1.0",
          deps: deps()
        ]
      end

      defp deps do
        [
          {:nbpr, "~> 0.6"},
          #{dep}
        ]
      end
    end
    """
  end
end
