defmodule NBPR.Artifact.Fetcher do
  @moduledoc """
  Orchestrates the fetch path.

  Given build inputs and a list of `artifact_sites`, plans against the
  registered resolvers and downloads the first one to succeed. The download
  lands at `NBPR.Artifact.download_path/1`. Extraction is `NBPR.Artifact.Cache`'s
  job and happens after a successful fetch.

  Resolvers are statically defined for production but may be overridden via
  the `:resolvers` opt — primarily a testing affordance.
  """

  alias NBPR.Artifact
  alias NBPR.Package

  @default_resolvers [
    NBPR.Artifact.Resolvers.GHCR,
    NBPR.Artifact.Resolvers.GitHubReleases
  ]

  @doc """
  Downloads the artefact tarball to its canonical download path. Returns the
  path on success; raises on total failure with an aggregated error message
  per resolver attempted.
  """
  @spec fetch!(Artifact.build_inputs(), [Package.artifact_site()], keyword()) :: Path.t()
  def fetch!(inputs, sites, opts \\ []) do
    resolvers = Keyword.get(opts, :resolvers, @default_resolvers)
    plans = build_plans(sites, inputs, resolvers)

    if plans == [] do
      raise """
      No resolver could plan a download for any of these sites: #{inspect(sites)}.
      Either no `artifact_sites:` are declared on the package, or none of the
      declared sites are handled by the available resolvers (#{inspect(resolvers)}).
      """
    end

    dest = Artifact.download_path(inputs)
    File.mkdir_p!(Path.dirname(dest))

    case try_plans(plans, dest) do
      :ok ->
        dest

      {:error, errors} ->
        raise build_error_message(inputs, errors)
    end
  end

  defp build_plans(sites, inputs, resolvers) do
    for site <- sites,
        plan = plan_for(site, inputs, resolvers),
        do: plan
  end

  defp plan_for(site, inputs, resolvers) do
    Enum.find_value(resolvers, fn resolver ->
      resolver.plan(site, inputs)
    end)
  end

  defp try_plans(plans, dest) do
    Enum.reduce_while(plans, {:error, []}, fn {mod, plan_data}, {:error, errors} ->
      case mod.get(plan_data, dest) do
        :ok ->
          {:halt, :ok}

        {:error, reason} ->
          {:cont, {:error, [{mod, reason} | errors]}}
      end
    end)
  end

  defp build_error_message(inputs, errors) do
    formatted =
      errors
      |> Enum.reverse()
      |> Enum.map_join("\n", fn {mod, reason} ->
        "  - #{inspect(mod)}: #{inspect(reason)}"
      end)

    """
    Failed to fetch #{Artifact.tarball_name(inputs)} from any configured site.

    Errors per resolver:
    #{formatted}
    """
  end
end
