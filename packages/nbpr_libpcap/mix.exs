defmodule Nbpr.Libpcap.MixProject do
  use Mix.Project

  @version "1.10.5"

  def project do
    [
      app: :nbpr_libpcap,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A system-independent library for user-level network packet capture.",
      package: [
        organization: "nbpr",
        licenses: ["BSD-3-Clause"],
        links: %{"GitHub" => "https://github.com/jimsynz/nbpr", "libpcap" => "https://www.tcpdump.org/"}
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
