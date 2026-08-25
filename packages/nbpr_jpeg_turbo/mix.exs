defmodule Nbpr.JpegTurbo.MixProject do
  use Mix.Project

  @version "3.1.4.1"

  def project do
    [
      app: :nbpr_jpeg_turbo,
      version: normalise_version(@version),
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "SIMD-accelerated JPEG codec providing the libjpeg API",
      package: [
        organization: "nbpr",
        licenses: ["IJG", "BSD-3-Clause", "Zlib"],
        links: %{
          "GitHub" => "https://github.com/jimsynz/nbpr",
          "jpeg-turbo" =>
            "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.1.4.1"
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
  # doesn't always match Hex's three-component shape: it can be
  # two-component (e.g. `2.92`), which we pad, or four (e.g. libjpeg-turbo's
  # `3.1.4.1`, a post-release fix tagged alongside `3.1.4`), which becomes
  # build metadata. `+d` keeps the upstream string recoverable and orders
  # between `3.1.3` and `3.1.5`; a `-d` pre-release would sort before the
  # `3.1.4` it supersedes.
  defp normalise_version(version) do
    case String.split(version, ".") do
      [major, minor] -> "#{major}.#{minor}.0"
      [major, minor, patch, extra] -> "#{major}.#{minor}.#{patch}+#{extra}"
      _ -> version
    end
  end
end
