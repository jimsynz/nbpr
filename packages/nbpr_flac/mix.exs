defmodule Nbpr.Flac.MixProject do
  use Mix.Project

  @version "1.5.0"

  def project do
    [
      app: :nbpr_flac,
      version: normalise_version(@version),
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Free Lossless Audio Codec libraries and command-line tools",
      package: [
        organization: "nbpr",
        licenses: ["BSD-3-Clause", "GPL-2.0-or-later", "LGPL-2.1-or-later"],
        links: %{
          "GitHub" => "https://github.com/jimsynz/nbpr",
          "flac" => "https://xiph.org/flac/"
        }
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      nbpr_dep(:nbpr, "~> 0.2"),
      nbpr_dep(:nbpr_libogg, "~> 1.0")
    ]
  end

  # Path dep for local dev (sibling in the workspace); Hex requirement
  # when publishing. Hex publish forbids path deps, so we switch the
  # spec only when the workflow asks for it. `:nbpr` itself lives on
  # public hex.pm; `:nbpr_*` packages live in the `nbpr` Hex org.
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

  # Renovate bumps @version straight to Buildroot's upstream value, which
  # can be two-component (e.g. `2.92`); pad to Hex's three-component shape.
  defp normalise_version(version) do
    case String.split(version, ".") do
      [major, minor] -> "#{major}.#{minor}.0"
      _ -> version
    end
  end
end
