defmodule NBPR.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/jimsynz/nbpr"

  def project do
    [
      app: :nbpr,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Nerves Binary Package Repository — library underpinning :nbpr_* packages",
      package: package(),
      docs: docs(),
      name: "NBPR",
      source_url: @source_url
    ]
  end

  def application do
    [
      mod: {NBPR.Application, []},
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:nimble_options, "~> 1.1"},
      {:muontrap, "~> 1.0"},
      # Optional — only required when a consumer runs `mix igniter.install
      # nbpr` to bootstrap their project. Listed here so `Mix.Tasks.Nbpr.Install`
      # compiles in this library's own build.
      {:igniter, "~> 0.7", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: @source_url,
      source_ref: "v#{@version}",
      groups_for_modules: [
        "Mix tasks": [
          Mix.Tasks.Nbpr.Build,
          Mix.Tasks.Nbpr.Fetch,
          Mix.Tasks.Nbpr.Inspect,
          Mix.Tasks.Nbpr.Install,
          Mix.Tasks.Nbpr.Matrix,
          Mix.Tasks.Nbpr.New,
          Mix.Tasks.Nbpr.Pack,
          Mix.Tasks.Nbpr.Publish,
          Mix.Tasks.Nbpr.Releasable
        ]
      ]
    ]
  end
end
