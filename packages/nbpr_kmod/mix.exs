defmodule Nbpr.Kmod.MixProject do
  use Mix.Project

  @version "34.2"

  def project do
    [
      app: :nbpr_kmod,
      version: normalise_version(@version),
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Kernel module tools (`insmod`, `modprobe`, `depmod`) and `libkmod` packaged for Nerves",
      package: [
        organization: "nbpr",
        licenses: ["LGPL-2.1-or-later", "GPL-2.0-or-later"],
        links: %{
          "kmod" => "https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git",
          "GitHub" => "https://github.com/jimsynz/nbpr"
        }
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

  # Renovate bumps @version straight to Buildroot's upstream value, which can
  # be two-component (e.g. `34.2`); pad to Hex's required three-component shape.
  defp normalise_version(version) do
    case String.split(version, ".") do
      [major] -> "#{major}.0.0"
      [major, minor] -> "#{major}.#{minor}.0"
      _ -> version
    end
  end
end
