defmodule Nbpr.Strace.MixProject do
  use Mix.Project

  @version "6.18.0"

  def project do
    [
      app: :nbpr_strace,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A useful diagnostic, instructional, and debugging tool.",
      package: [
        organization: "nbpr",
        licenses: ["LGPL-2.1-or-later"],
        links: %{"GitHub" => "https://github.com/jimsynz/nbpr", "strace" => "https://strace.io"}
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
