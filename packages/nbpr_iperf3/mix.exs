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
    [nbpr_dep()]
  end

  # Path dep for local dev (sibling `:nbpr/` in the workspace); Hex
  # requirement against the `nbpr` organisation when publishing. Hex
  # publish forbids path deps, so we switch the spec only when the
  # workflow asks for it.
  defp nbpr_dep do
    case System.get_env("NBPR_RELEASE") do
      "1" -> {:nbpr, "~> 0.1", organization: "nbpr"}
      _ -> {:nbpr, path: "../../nbpr"}
    end
  end
end
