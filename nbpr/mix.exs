defmodule NBPR.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :nbpr,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Nerves Binary Package Repository — library underpinning :nbpr_* packages",
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:nimble_options, "~> 1.1"},
      {:muontrap, "~> 1.0"}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/nerves-project/nbpr"}
    ]
  end
end
