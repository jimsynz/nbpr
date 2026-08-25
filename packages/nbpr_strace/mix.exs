defmodule Nbpr.Strace.MixProject do
  use Mix.Project

  @version "6.18.0"

  def project do
    [
      app: :nbpr_strace,
      version: normalise_version(@version),
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

  # Renovate writes Buildroot's upstream version straight into @version,
  # and Buildroot's versions aren't semver: they can be short (`2.92`),
  # carry a fourth component (`3.1.4.1`) or a patchlevel suffix
  # (`7.1.2-26`). hex.pm takes exactly MAJOR.MINOR.PATCH — it rejects
  # build metadata outright, and a pre-release is invisible to a `~>`
  # requirement — so pad what's short and drop a trailing numeric
  # packaging component. `NBPR.Version` documents the rules and the cost.
  defp normalise_version(version) do
    upstream = ~r/^0*(?<major>\d+)(?:\.0*(?<minor>\d+))?(?:\.0*(?<patch>\d+))?(?:[.-]\d+)*$/

    case Regex.named_captures(upstream, version) do
      %{"major" => major, "minor" => minor, "patch" => patch} ->
        Enum.map_join([major, minor, patch], ".", fn
          "" -> "0"
          segment -> segment
        end)

      nil ->
        version
    end
  end
end
