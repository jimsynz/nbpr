defmodule Nbpr.Hailo10.MixProject do
  use Mix.Project

  # Tracks the upstream HailoRT release this package builds (v5 line).
  @version "5.3.0"

  def project do
    [
      app: :nbpr_hailo10,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "HailoRT v5 runtime, PCIe driver and firmware for Hailo-10H AI accelerators, packaged for Nerves",
      package: [
        organization: "nbpr",
        licenses: ["MIT", "GPL-2.0"],
        files: ~w(lib buildroot mix.exs README.md),
        links: %{
          "HailoRT" => "https://github.com/hailo-ai/hailort",
          "hailort-drivers" => "https://github.com/hailo-ai/hailort-drivers",
          "GitHub" => "https://github.com/jimsynz/nbpr"
        }
      ]
    ]
  end

  def application do
    [
      mod: {NBPR.Hailo10.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      nbpr_dep(:nbpr, "~> 0.2"),
      # Ships insmod/modinfo that NBPR.Runtime.load_kernel_module!/2 uses to load
      # hailo1x_pci by path at boot (see kernel_modules: above).
      nbpr_dep(:nbpr_kmod, "~> 34.0")
    ]
  end

  defp nbpr_dep(:nbpr = name, requirement) do
    case System.get_env("NBPR_RELEASE") do
      "1" -> {name, requirement}
      _ -> {name, path: "../../nbpr"}
    end
  end

  defp nbpr_dep(name, requirement) do
    case System.get_env("NBPR_RELEASE") do
      "1" -> {name, requirement, organization: "nbpr"}
      _ -> {name, path: "../" <> Atom.to_string(name)}
    end
  end
end
