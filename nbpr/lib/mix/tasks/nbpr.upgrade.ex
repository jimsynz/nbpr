if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Nbpr.Upgrade do
    @shortdoc "Upgrades a project's NBPR configuration between `:nbpr` versions"

    @moduledoc """
    Upgrade steps run by `mix igniter.upgrade nbpr`.

    ## 0.7.0

    The `:nbpr_*` packages moved from the `nbpr` Hex organisation to public
    hex.pm. This step:

    - removes `organization: "nbpr"` from every dependency in `mix.exs`;
    - unlocks every dependency `mix.lock` resolved from the organisation, so
      the next `mix deps.get` fetches them from hex.pm instead.
    """

    use Igniter.Mix.Task

    @nbpr_org_repo "hexpm:nbpr"

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :nbpr,
        example: "mix igniter.upgrade nbpr",
        positional: [:from, :to]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      upgrades = %{"0.7.0" => [&leave_nbpr_organisation/2]}

      Igniter.Upgrades.run(
        igniter,
        igniter.args.positional.from,
        igniter.args.positional.to,
        upgrades,
        igniter.args.options
      )
    end

    defp leave_nbpr_organisation(igniter, _opts) do
      igniter
      |> Igniter.update_elixir_file("mix.exs", fn zipper ->
        Igniter.Code.Common.update_all_matches(
          zipper,
          &nbpr_org_dep?/1,
          &drop_organisation/1
        )
      end)
      |> unlock_org_deps()
      |> Igniter.add_notice("""
      The `:nbpr_*` packages now live on public hex.pm rather than the `nbpr`
      Hex organisation, so `organization: "nbpr"` has been removed from your
      deps. The organisation's read key no longer works; you can remove it
      from your machine's Hex config with:

          mix hex.organization deauth nbpr
      """)
    end

    defp nbpr_org_dep?(zipper) do
      with true <- Igniter.Code.Tuple.tuple?(zipper),
           {:ok, opts} <- Igniter.Code.Tuple.tuple_elem(zipper, 2),
           true <- Igniter.Code.List.list?(opts),
           {:ok, organisation} <- Igniter.Code.Keyword.get_key(opts, :organization) do
        Igniter.Code.Common.nodes_equal?(organisation, "nbpr")
      else
        _ -> false
      end
    end

    defp drop_organisation(zipper) do
      {:ok, opts} = Igniter.Code.Tuple.tuple_elem(zipper, 2)
      {:ok, opts} = Igniter.Code.Keyword.remove_keyword_key(opts, :organization)

      case Sourceror.Zipper.node(opts) do
        [] ->
          {:ok, name} = Igniter.Code.Tuple.tuple_elem(zipper, 0)
          {:ok, requirement} = Igniter.Code.Tuple.tuple_elem(zipper, 1)

          {:code,
           {:__block__, [], [{Sourceror.Zipper.node(name), Sourceror.Zipper.node(requirement)}]}}

        _ ->
          {:ok, Sourceror.Zipper.up(opts)}
      end
    end

    defp unlock_org_deps(igniter) do
      case org_locked_deps(igniter) do
        [] -> igniter
        names -> Igniter.add_task(igniter, "deps.unlock", names)
      end
    end

    defp org_locked_deps(igniter) do
      if Igniter.exists?(igniter, "mix.lock") do
        igniter
        |> Igniter.include_existing_file("mix.lock")
        |> Map.get(:rewrite)
        |> Rewrite.source!("mix.lock")
        |> Rewrite.Source.get(:content)
        |> Code.string_to_quoted!(emit_warnings: false)
        |> Code.eval_quoted()
        |> elem(0)
        |> Enum.flat_map(fn
          {name, {:hex, _, _, _, _, _, @nbpr_org_repo, _}} -> [to_string(name)]
          _ -> []
        end)
        |> Enum.sort()
      else
        []
      end
    end
  end
end
