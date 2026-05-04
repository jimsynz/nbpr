defmodule Mix.Tasks.Nbpr.CatalogueTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Nbpr.Catalogue

  describe "catalogue_markdown/1" do
    test "renders a row per package with name, version, and description" do
      pkgs = [
        %{name: "nbpr_jq", version: "1.8.1", description: "JSON processor"},
        %{name: "nbpr_dnsmasq", version: "2.91.0", description: "DHCP/DNS server"}
      ]

      md = Catalogue.catalogue_markdown(pkgs)

      assert md =~
               "| [`:nbpr_jq`](https://hex.pm/packages/nbpr/nbpr_jq) | 1.8.1 | JSON processor |"

      assert md =~
               "| [`:nbpr_dnsmasq`](https://hex.pm/packages/nbpr/nbpr_dnsmasq) | 2.91.0 | DHCP/DNS server |"
    end

    test "shows a placeholder for an empty workspace" do
      md = Catalogue.catalogue_markdown([])
      assert md =~ "No packages in the workspace yet"
      refute md =~ "| Package |"
    end

    test "escapes pipe characters in descriptions so the table doesn't break" do
      pkgs = [%{name: "nbpr_x", version: "1.0.0", description: "foo|bar"}]
      md = Catalogue.catalogue_markdown(pkgs)

      assert md =~ "foo\\|bar"
    end
  end

  describe "run/1" do
    test "scans packages/ in the given root and writes to the given output" do
      root = build_workspace!()
      output = Path.join(root, "out.md")

      capture_out(fn ->
        Catalogue.run(["--root", root, "--output", output])
      end)

      contents = File.read!(output)

      assert contents =~ "| [`:nbpr_one`](https://hex.pm/packages/nbpr/nbpr_one) | 1.0.0 |"
      assert contents =~ "| [`:nbpr_two`](https://hex.pm/packages/nbpr/nbpr_two) | 2.5.3 |"
    end

    test "produces a valid catalogue when packages/ is empty" do
      root = Path.join(System.tmp_dir!(), "nbpr_cat_empty_#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "packages"))
      on_exit(fn -> File.rm_rf!(root) end)

      output = Path.join(root, "out.md")

      capture_out(fn ->
        Catalogue.run(["--root", root, "--output", output])
      end)

      assert File.read!(output) =~ "No packages in the workspace yet"
    end
  end

  defp build_workspace! do
    root = Path.join(System.tmp_dir!(), "nbpr_cat_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "packages"))
    on_exit(fn -> File.rm_rf!(root) end)

    write_pkg!(root, "nbpr_one", "1.0.0", "Package one's description")
    write_pkg!(root, "nbpr_two", "2.5.3", "Package two's description")

    root
  end

  defp write_pkg!(root, name, version, description) do
    pkg_dir = Path.join([root, "packages", name])
    File.mkdir_p!(pkg_dir)

    File.write!(Path.join(pkg_dir, "mix.exs"), """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project
      @version "#{version}"
      def project, do: [app: :#{name}, version: @version, description: "#{description}"]
    end
    """)
  end

  defp capture_out(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end
end
