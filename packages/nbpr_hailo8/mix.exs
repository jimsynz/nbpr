defmodule Nbpr.Hailo8.MixProject do
  use Mix.Project

  # Tracks the upstream HailoRT release this package builds (hailo8 branch).
  @version "4.24.0"

  def project do
    [
      app: :nbpr_hailo8,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "HailoRT runtime, PCIe driver and firmware for Hailo-8/8L AI accelerators, packaged for Nerves",
      package: [
        organization: "nbpr",
        # The wrapper + Buildroot recipes; the artefact bundles libhailort
        # (MIT) and the hailo_pci driver (GPL-2.0). The Hailo-8 firmware blob
        # is proprietary and fetched from Hailo at build time, not shipped here.
        licenses: ["MIT", "GPL-2.0-only"],
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
    # The generated NBPR.Hailo8.Application insmods the hailo_pci module at boot
    # on a Nerves target (no-op on host).
    [
      mod: {NBPR.Hailo8.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      nbpr_dep(:nbpr, "~> 0.2"),
      # Ships insmod/modinfo that NBPR.Runtime.load_kernel_module!/2 uses to load
      # hailo_pci by path at boot (see kernel_modules: above).
      nbpr_dep(:nbpr_kmod, "~> 34.0")
    ]
  end

  # Path dep for local dev (sibling in the workspace); Hex requirement when
  # publishing. Hex publish forbids path deps, so we switch the spec only when
  # the workflow asks for it. `:nbpr` itself lives on public hex.pm; the
  # `:nbpr_*` packages live in the `nbpr` Hex org.
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
