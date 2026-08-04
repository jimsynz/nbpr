defmodule Nbpr.Ncurses.MixProject do
  use Mix.Project

  # Buildroot builds ncurses from a dated snapshot: `NCURSES_VERSION` is
  # `$(NCURSES_VERSION_MAJOR)-$(NCURSES_SNAPSHOT_DATE)` (e.g. `6.6-20251231`),
  # which is neither a Hex version nor something the buildroot-package
  # Renovate datasource can read. So this tracks `NCURSES_VERSION_MAJOR`
  # alone; nbpr-side rebuilds against a newer snapshot of the same major go
  # in the patch position: `6.6.1`, `6.6.2`, etc.
  @version "6.6"

  def project do
    [
      app: :nbpr_ncurses,
      version: normalise_version(@version),
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Terminal-handling library for curses-style TUI programs (`ncurses`) packaged for Nerves",
      package: [
        organization: "nbpr",
        licenses: ["X11-distribute-modifications-variant"],
        links: %{
          "GitHub" => "https://github.com/jimsynz/nbpr",
          "ncurses" => "https://invisible-island.net/ncurses/"
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
  # can be two-component (e.g. `2.92`); pad to Hex's three-component shape.
  defp normalise_version(version) do
    case String.split(version, ".") do
      [major, minor] -> "#{major}.#{minor}.0"
      _ -> version
    end
  end
end
