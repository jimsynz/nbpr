defmodule Nbpr.Jq.MixProject do
  use Mix.Project

  @version "1.7.1"

  def project do
    [
      app: :nbpr_jq,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Lightweight JSON processor (`jq`) packaged for Nerves",
      package: [
        licenses: ["MIT"],
        links: %{"jq" => "https://jqlang.github.io/jq/"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:nbpr, path: "../../nbpr"}
    ]
  end
end
