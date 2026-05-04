defmodule Nbpr.Iperf3.MixProject do
  use Mix.Project

  @version "3.19.1"

  def project do
    [
      app: :nbpr_iperf3,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Iperf is a tool for active measurements of the maximum achievable bandwidth on IP networks.",
      package: [
        organization: "nbpr",
        licenses: ["BSD-3-Clause", "BSD-2-Clause", "MIT"],
        links: %{"GitHub" => "https://github.com/jimsynz/nbpr", "iperf3" => "http://software.es.net/iperf/index.html"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      nbpr_dep(:nbpr, "~> 0.2")
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
