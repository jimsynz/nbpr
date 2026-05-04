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
      nbpr_dep(),
      {:nbpr_libpcap, "~> 1.10", organization: "nbpr", override: true}
    ]
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
