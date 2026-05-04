defmodule Nbpr.Tcpdump.MixProject do
  use Mix.Project

  @version "4.99.5"

  def project do
    [
      app: :nbpr_tcpdump,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A tool for network monitoring and data acquisition.",
      package: [
        organization: "nbpr",
        licenses: ["BSD-3-Clause"],
        links: %{"GitHub" => "https://github.com/jimsynz/nbpr", "tcpdump" => "https://www.tcpdump.org/"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      nbpr_dep(:nbpr, "~> 0.2"),
      nbpr_dep(:nbpr_libpcap, "~> 1.10")
    ]
  end

  # Path dep for local dev (sibling in the workspace); Hex requirement
  # when publishing. Hex publish forbids path deps, so we switch the spec
  # only when the workflow asks for it. `:nbpr` itself lives on public
  # hex.pm; `:nbpr_*` packages live in the `nbpr` Hex org.
  defp nbpr_dep(:nbpr = name, requirement) do
    case System.get_env("NBPR_RELEASE") do
      "1" -> {name, requirement}
      _ -> {name, path: nbpr_dep_path(name)}
    end
  end

  defp nbpr_dep(name, requirement) do
    case System.get_env("NBPR_RELEASE") do
      "1" -> {name, requirement, organization: "nbpr"}
      _ -> {name, path: nbpr_dep_path(name)}
    end
  end

  defp nbpr_dep_path(:nbpr), do: "../../nbpr"
  defp nbpr_dep_path(name) when is_atom(name), do: "../" <> Atom.to_string(name)
end
