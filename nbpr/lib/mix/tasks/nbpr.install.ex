defmodule Mix.Tasks.Nbpr.Install do
  @shortdoc "Configure a Nerves project to consume :nbpr_* binary packages"

  @moduledoc """
  Installs and configures NBPR in a Nerves project so it can consume
  binary packages from the `nbpr` Hex organisation.

      mix igniter.install nbpr

  ## What this does

  - Adds `:nbpr` to the project's deps (handled by `mix igniter.install`).
  - Merges `firmware: ["nbpr.fetch", "firmware"]` into `aliases:` in
    `mix.exs` so `mix firmware` runs `mix nbpr.fetch` first to populate
    prebuilt binaries from GHCR.
  - Authenticates the local Hex client to the `nbpr` organisation using
    the publicly-shared read key, so subsequent `mix deps.get` calls can
    fetch `:nbpr_*` packages.

  After running, add the binary packages you want to your `deps/0`:

      {:nbpr_jq, "~> 1.0", organization: "nbpr"},
      {:nbpr_dnsmasq, "~> 2.0", organization: "nbpr"}

  Daemon-bearing packages (e.g. `:nbpr_dnsmasq`) generate a supervised
  module — add it to your supervision tree:

      children = [
        {NBPR.Dnsmasq.Dnsmasq, config_file: "/etc/dnsmasq.conf"}
      ]
  """

  use Igniter.Mix.Task

  # The `nbpr` organisation's read key is intentionally public — it gates
  # discoverability of the org's binary packages, not access to private
  # content. Same key documented in the project README.
  @public_read_key "15da04a2330d881e1301a73c5d39f591"

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :nbpr,
      example: "mix igniter.install nbpr"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    igniter
    |> add_firmware_alias()
    |> Igniter.add_task("hex.organization", ["auth", "nbpr", "--key", @public_read_key])
    |> Igniter.add_notice("""
    NBPR is installed. To pull in binary packages, add them to your
    deps/0 with `organization: "nbpr"`:

        {:nbpr_jq, "~> 1.0", organization: "nbpr"},
        {:nbpr_dnsmasq, "~> 2.0", organization: "nbpr"}

    See https://github.com/jimsynz/nbpr for the catalogue.
    """)
  end

  # Idempotent: prepends `"nbpr.fetch"` to an existing `:firmware` alias,
  # creates the alias from scratch when missing, and skips the prepend if
  # `"nbpr.fetch"` is already at the head of the list.
  defp add_firmware_alias(igniter) do
    Igniter.Project.MixProject.update(igniter, :project, [:aliases, :firmware], fn
      nil ->
        {:ok, {:code, Sourceror.parse_string!(~s(["nbpr.fetch", "firmware"]))}}

      zipper ->
        Igniter.Code.List.prepend_new_to_list(zipper, "nbpr.fetch")
    end)
  end
end
