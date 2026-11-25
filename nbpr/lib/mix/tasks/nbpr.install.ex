# Igniter is an optional dep — consumers of `:nbpr` who don't pull it in
# (i.e. nearly everyone, including the sibling `:nbpr_*` packages) skip
# this module entirely. The compile-time guard means it's only defined
# when Igniter is in the build context, which is the case for users who
# invoke `mix igniter.install nbpr` (igniter brings itself in) and for
# the `:nbpr` library's own dev/test environment.
if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Nbpr.Install do
    @shortdoc "Configure a Nerves project to consume :nbpr_* binary packages"

    @moduledoc """
    Installs and configures NBPR in a Nerves project so it can consume
    `:nbpr_*` binary packages.

        mix igniter.install nbpr

    ## What this does

    - Adds `:nbpr` to the project's deps (handled by `mix igniter.install`).
    - Merges `firmware: ["nbpr.fetch", "firmware"]` into `aliases:` in
      `mix.exs` so `mix firmware` runs `mix nbpr.fetch` first to populate
      prebuilt binaries from GHCR.

    After running, add the binary packages you want to your `deps/0`:

        {:nbpr_jq, "~> 1.8"},
        {:nbpr_dnsmasq, "~> 2.92"}

    Daemon-bearing packages (e.g. `:nbpr_dnsmasq`) generate a supervised
    module — add it to your supervision tree:

        children = [
          {NBPR.Dnsmasq.Dnsmasq, config_file: "/etc/dnsmasq.conf"}
        ]
    """

    use Igniter.Mix.Task

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
      |> Igniter.add_notice("""
      NBPR is installed. To pull in binary packages, add them to your
      deps/0:

          {:nbpr_jq, "~> 1.8"},
          {:nbpr_dnsmasq, "~> 2.92"}

      See https://nbpr.hexdocs.pm/catalogue.html for the catalogue.
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
end
