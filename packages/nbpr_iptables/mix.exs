defmodule Nbpr.Iptables.MixProject do
  use Mix.Project

  @version "1.8.11"

  def project do
    [
      app: :nbpr_iptables,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Linux kernel firewall, NAT, and packet mangling tools.",
      package: [
        organization: "nbpr",
        licenses: ["GPL-2.0-only"],
        links: %{"GitHub" => "https://github.com/jimsynz/nbpr", "iptables" => "http://www.netfilter.org/projects/iptables/index.html"}
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
end
