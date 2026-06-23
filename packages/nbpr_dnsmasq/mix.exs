defmodule Nbpr.Dnsmasq.MixProject do
  use Mix.Project

  # Tracks upstream dnsmasq, which is often two-component (e.g. `2.91`, `2.92`).
  # Renovate bumps this attribute straight to Buildroot's value, so it may not
  # be a valid Hex version on its own — `normalise_version/1` pads it to the
  # three-component shape Hex requires. nbpr-side rebuilds of the same upstream
  # version go in the patch position: `2.91.1`, `2.91.2`, etc.
  @version "2.92"

  def project do
    [
      app: :nbpr_dnsmasq,
      version: normalise_version(@version),
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Lightweight DHCP/DNS server (`dnsmasq`) packaged for Nerves",
      package: [
        organization: "nbpr",
        licenses: ["GPL-2.0-or-later"],
        links: %{
          "dnsmasq" => "https://thekelleys.org.uk/dnsmasq/doc.html",
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

  # Pads a two-component upstream version (`2.92`) to Hex's required
  # three-component shape (`2.92.0`); leaves a complete version untouched.
  defp normalise_version(version) do
    case String.split(version, ".") do
      [major, minor] -> "#{major}.#{minor}.0"
      _ -> version
    end
  end
end
