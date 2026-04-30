defmodule Nbpr.Dnsmasq.MixProject do
  use Mix.Project

  # Upstream dnsmasq is `2.91` (no patch component); we pad to `.0` for Hex's
  # required semver shape. Bumps for nbpr-side rebuilds of the same upstream
  # version go in the patch position: `2.91.1`, `2.91.2`, etc.
  @version "2.91.0"

  def project do
    [
      app: :nbpr_dnsmasq,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Lightweight DHCP/DNS server (`dnsmasq`) packaged for Nerves",
      package: [
        licenses: ["GPL-2.0-only"],
        links: %{"dnsmasq" => "https://thekelleys.org.uk/dnsmasq/doc.html"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:nbpr, path: "../../nbpr"}
    ]
  end
end
