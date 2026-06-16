defmodule Mix.Tasks.Nbpr.Cache do
  @shortdoc "Inspect and clean the local NBPR artefact cache"

  @moduledoc """
  Introspect and garbage-collect the extracted-artefact cache that
  `mix nbpr.fetch`/`mix nbpr.build` populate under
  `$NERVES_ARTIFACTS_DIR/nbpr/` (defaulting to `~/.local/share/nerves/nbpr/`).

      mix nbpr.cache list
      mix nbpr.cache info <dir>
      mix nbpr.cache clean [--keep-latest] [--dry-run] [--yes]

  ## Subcommands

    * `list` — one line per cached artefact: directory name, package version,
      and target system.
    * `info <dir>` — the full `(package, version, system, system_version,
      build_opts)` tuple a cache entry corresponds to, read from its
      `manifest.json`. `<dir>` is the directory name as printed by `list`.
    * `clean` — remove cached artefacts. By default removes **all** of them;
      with `--keep-latest` it keeps the most-recently-modified entry per
      package and removes the rest. Prompts before deleting unless `--yes` is
      given; `--dry-run` prints what would be removed without deleting.
  """

  use Mix.Task

  alias NBPR.Artifact.Cache

  @switches [keep_latest: :boolean, dry_run: :boolean, yes: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, positional} = OptionParser.parse!(args, strict: @switches)

    case positional do
      ["list"] ->
        list()

      ["info", dir] ->
        info(dir)

      ["clean"] ->
        clean(opts)

      _ ->
        Mix.raise(
          "usage: mix nbpr.cache list | info <dir> | clean [--keep-latest] [--dry-run] [--yes]"
        )
    end
  end

  defp list do
    case Cache.list() do
      [] ->
        Mix.shell().info("[nbpr] cache is empty (#{NBPR.Artifact.cache_root()})")

      entries ->
        Enum.each(entries, fn entry -> Mix.shell().info(summarise(entry)) end)

        Mix.shell().info(
          "\n#{length(entries)} cached artefact(s) in #{NBPR.Artifact.cache_root()}"
        )
    end
  end

  defp info(dir) do
    case Enum.find(Cache.list(), &(&1.dir == dir)) do
      nil ->
        Mix.raise(
          "no cache entry named #{inspect(dir)}; run `mix nbpr.cache list` to see what's cached"
        )

      %{manifest: nil} = entry ->
        Mix.raise("cache entry #{inspect(entry.dir)} has no readable manifest.json")

      %{manifest: manifest} = entry ->
        Mix.shell().info(detail(entry, manifest))
    end
  end

  defp clean(opts) do
    entries = Cache.list()
    to_remove = entries_to_remove(entries, opts)

    cond do
      to_remove == [] ->
        Mix.shell().info("[nbpr] nothing to remove")

      opts[:dry_run] ->
        Mix.shell().info("[nbpr] would remove #{length(to_remove)} entr(y/ies):")
        Enum.each(to_remove, &Mix.shell().info("  - #{&1.dir}"))

      opts[:yes] or confirm_removal(to_remove) ->
        Enum.each(to_remove, fn entry -> Cache.remove!(entry.path) end)
        Mix.shell().info("[nbpr] removed #{length(to_remove)} entr(y/ies)")

      true ->
        Mix.shell().info("[nbpr] aborted; nothing removed")
    end
  end

  @doc false
  @spec entries_to_remove([Cache.entry()], keyword()) :: [Cache.entry()]
  def entries_to_remove(entries, opts) do
    if opts[:keep_latest] do
      entries
      |> Enum.group_by(&package_of/1)
      |> Enum.flat_map(fn {_package, group} ->
        group |> Enum.sort_by(& &1.mtime, :desc) |> Enum.drop(1)
      end)
    else
      entries
    end
  end

  defp confirm_removal(to_remove) do
    Mix.shell().info("[nbpr] about to remove #{length(to_remove)} cache entr(y/ies):")
    Enum.each(to_remove, &Mix.shell().info("  - #{&1.dir}"))
    Mix.shell().yes?("Continue?")
  end

  defp summarise(%{dir: dir, manifest: nil}), do: "#{dir}  (no manifest)"

  defp summarise(%{dir: dir, manifest: manifest}) do
    "#{dir}  [#{manifest["package_name"]} #{manifest["package_version"]} → " <>
      "#{manifest["system_app"]} #{manifest["system_version"]}]"
  end

  defp detail(entry, manifest) do
    """
    #{entry.dir}

      package:        #{manifest["package_name"]} #{manifest["package_version"]}
      system:         #{manifest["system_app"]} #{manifest["system_version"]}
      cache key:      #{manifest["cache_key"]}
      schema version: #{manifest["schema_version"]}
      build opts:     #{format_build_opts(manifest["build_opts"])}
      path:           #{entry.path}
    """
    |> String.trim_trailing()
  end

  defp format_build_opts(opts) when opts == %{} or is_nil(opts), do: "(none)"

  defp format_build_opts(opts) do
    opts
    |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
    |> Enum.join(", ")
  end

  defp package_of(%{manifest: %{"package_name" => name}}) when is_binary(name), do: name
  defp package_of(%{dir: dir}), do: dir
end
