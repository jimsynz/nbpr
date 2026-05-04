defmodule Mix.Tasks.Nbpr.ReleasableTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Nbpr.Releasable

  describe "compute/2" do
    test "lists packages whose local version is ahead of Hex, topo-sorted" do
      root =
        build_workspace!(%{
          "nbpr" => {"0.1.0", []},
          "nbpr_libpcap" => {"1.10.5", [:nbpr]},
          "nbpr_tcpdump" => {"4.99.5", [:nbpr, :nbpr_libpcap]}
        })

      hex = fn
        "nbpr" -> {:ok, "0.1.0"}
        _ -> :not_found
      end

      result = Releasable.compute(root, hex)

      assert Enum.map(result, & &1.name) == ["nbpr_libpcap", "nbpr_tcpdump"]
      assert Enum.find(result, &(&1.name == "nbpr_libpcap")).tag == "nbpr_libpcap-v1.10.5"
      assert Enum.find(result, &(&1.name == "nbpr_tcpdump")).tag == "nbpr_tcpdump-v4.99.5"
    end

    test "skips packages whose local version matches Hex" do
      root =
        build_workspace!(%{
          "nbpr" => {"0.1.0", []},
          "nbpr_jq" => {"1.8.1", [:nbpr]}
        })

      hex = fn
        "nbpr" -> {:ok, "0.1.0"}
        "nbpr_jq" -> {:ok, "1.8.1"}
      end

      assert Releasable.compute(root, hex) == []
    end

    test "treats local-ahead-of-Hex as releasable" do
      root =
        build_workspace!(%{
          "nbpr" => {"0.1.0", []},
          "nbpr_jq" => {"1.8.2", [:nbpr]}
        })

      hex = fn
        "nbpr" -> {:ok, "0.1.0"}
        "nbpr_jq" -> {:ok, "1.8.1"}
      end

      assert [%{name: "nbpr_jq", version: "1.8.2"}] = Releasable.compute(root, hex)
    end

    test "puts :nbpr first when both library and packages bump together" do
      root =
        build_workspace!(%{
          "nbpr" => {"0.2.0", []},
          "nbpr_libpcap" => {"1.10.6", [:nbpr]},
          "nbpr_tcpdump" => {"4.99.6", [:nbpr, :nbpr_libpcap]}
        })

      hex = fn _ -> :not_found end

      assert ["nbpr", "nbpr_libpcap", "nbpr_tcpdump"] =
               Releasable.compute(root, hex) |> Enum.map(& &1.name)
    end

    test "ignores dep edges into packages that aren't being released" do
      # libpcap is current on Hex; tcpdump bumps but doesn't need to wait
      # for libpcap (since libpcap isn't being released this round).
      root =
        build_workspace!(%{
          "nbpr" => {"0.1.0", []},
          "nbpr_libpcap" => {"1.10.5", [:nbpr]},
          "nbpr_tcpdump" => {"4.99.6", [:nbpr, :nbpr_libpcap]}
        })

      hex = fn
        "nbpr" -> {:ok, "0.1.0"}
        "nbpr_libpcap" -> {:ok, "1.10.5"}
        "nbpr_tcpdump" -> {:ok, "4.99.5"}
      end

      assert [%{name: "nbpr_tcpdump"}] = Releasable.compute(root, hex)
    end

    test "raises on Hex transport errors" do
      root = build_workspace!(%{"nbpr" => {"0.1.0", []}})

      hex = fn _ -> {:error, :timeout} end

      assert_raise Mix.Error, ~r/Hex lookup for nbpr failed/, fn ->
        Releasable.compute(root, hex)
      end
    end
  end

  defp build_workspace!(spec) do
    root =
      Path.join(System.tmp_dir!(), "nbpr_releasable_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    Enum.each(spec, fn
      {"nbpr", {version, _deps}} ->
        File.mkdir_p!(Path.join(root, "nbpr"))

        File.write!(Path.join([root, "nbpr", "mix.exs"]), """
        defmodule Nbpr.MixProject do
          use Mix.Project
          @version "#{version}"
          def project, do: [app: :nbpr, version: @version]
        end
        """)

      {name, {version, deps}} ->
        pkg_dir = Path.join([root, "packages", name])
        File.mkdir_p!(pkg_dir)

        deps_block =
          deps
          |> Enum.map(fn dep -> ~s|      nbpr_dep(:#{dep}, "~> 0.1")| end)
          |> Enum.join(",\n")

        File.write!(Path.join(pkg_dir, "mix.exs"), """
        defmodule Nbpr.#{Macro.camelize(String.replace_prefix(name, "nbpr_", ""))}.MixProject do
          use Mix.Project
          @version "#{version}"
          def project, do: [app: :#{name}, version: @version, deps: deps()]

          defp deps do
            [
        #{deps_block}
            ]
          end

          defp nbpr_dep(name, requirement) do
            {name, requirement, organization: "nbpr"}
          end
        end
        """)
    end)

    root
  end
end
