defmodule Mix.Tasks.Nbpr.Releasable do
  @shortdoc "List packages whose @version is ahead of Hex, in publish order"

  @moduledoc """
  Diffs each package's `mix.exs` `@version` against the latest version
  published to the `nbpr` Hex organisation, returning the topo-sorted
  list of packages that need a fresh release tag.

      mix nbpr.releasable [--json] [--root <path>]

  Reads `NBPR_READ_KEY` from the environment for the Hex org API. Without
  it, the org-scoped lookups fail with HTTP 401 and the task aborts.

  ## Topological order

  Every `:nbpr_*` package depends on `:nbpr`, so when both bump in the
  same push, `:nbpr` is emitted first. Sibling deps declared via
  `nbpr_dep(:nbpr_<x>, ...)` are honoured: `nbpr_tcpdump` (which depends
  on `nbpr_libpcap`) lands after `nbpr_libpcap` in the output.

  ## Output

  Without flags: human-readable lines, one per releasable.

  With `--json`: a JSON array; consumed by `auto-release.yml`.

      [
        {"name":"nbpr","version":"0.1.0","tag":"nbpr-v0.1.0","hex_version":null},
        {"name":"nbpr_libpcap","version":"1.10.5","tag":"nbpr_libpcap-v1.10.5","hex_version":null}
      ]

  ## Flags

    * `--json` — emit a JSON array
    * `--root <path>` — workspace root (defaults to current directory)
  """

  use Mix.Task

  @switches [json: :boolean, root: :string]

  @hex_org "nbpr"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    root = opts[:root] || File.cwd!()

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    entries = compute(root, &fetch_hex_version/1)

    if opts[:json] do
      Mix.shell().info(IO.iodata_to_binary(:json.encode(json_friendly(entries))))
    else
      print_human(entries)
    end
  end

  # OTP's `:json.encode/1` emits unknown atoms as their string name (so `nil`
  # → `"nil"`); only the literal atom `:null` becomes JSON `null`. Map our
  # `hex_version: nil` (genuinely "no published version") to `:null` before
  # encoding so downstream consumers get a real null.
  defp json_friendly(entries) do
    Enum.map(entries, fn entry ->
      Map.update!(entry, :hex_version, fn
        nil -> :null
        v -> v
      end)
    end)
  end

  @doc """
  Computes the topo-sorted list of releasable packages.

  `hex_lookup` is a 1-arity function called with each package name; it
  must return `{:ok, version}` for an existing Hex package, `:not_found`
  if Hex doesn't know about the package, or `{:error, reason}` for
  transport failures (which abort the run).
  """
  @spec compute(Path.t(), (String.t() -> {:ok, String.t()} | :not_found | {:error, term()})) ::
          [
            %{
              name: String.t(),
              version: String.t(),
              tag: String.t(),
              hex_version: String.t() | nil,
              deps: [String.t()]
            }
          ]
  def compute(root, hex_lookup) do
    workspace = scan_workspace(root)

    workspace
    |> Enum.map(&with_hex_version(&1, hex_lookup))
    |> Enum.filter(&needs_release?/1)
    |> topo_sort()
    |> Enum.map(&Map.put(&1, :tag, "#{&1.name}-v#{&1.version}"))
    |> Enum.map(&Map.take(&1, [:name, :version, :tag, :hex_version, :deps]))
  end

  defp scan_workspace(root) do
    [scan_lib(root) | scan_packages(root)]
  end

  defp scan_lib(root) do
    mix_path = Path.join([root, "nbpr", "mix.exs"])

    unless File.exists?(mix_path) do
      Mix.raise("missing #{mix_path} — run from the workspace root")
    end

    contents = File.read!(mix_path)

    %{
      name: "nbpr",
      version: extract_version!(contents, mix_path),
      deps: extract_sibling_deps(contents)
    }
  end

  defp scan_packages(root) do
    root
    |> Path.join("packages/nbpr_*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.sort()
    |> Enum.map(fn dir ->
      name = Path.basename(dir)
      mix_path = Path.join(dir, "mix.exs")
      contents = File.read!(mix_path)

      %{
        name: name,
        version: extract_version!(contents, mix_path),
        deps: extract_sibling_deps(contents)
      }
    end)
  end

  defp extract_version!(contents, mix_path) do
    case Regex.run(~r/@version\s+"([^"]+)"/, contents) do
      [_, version] -> version
      _ -> Mix.raise("no @version declaration in #{mix_path}")
    end
  end

  # Extracts every `nbpr_dep(:<name>, ...)` invocation. `:nbpr` is included
  # because `:nbpr_*` packages always depend on it (the helper enforces
  # this), which gives us a single source of truth for the dep graph.
  defp extract_sibling_deps(contents) do
    ~r/nbpr_dep\(:([a-z][a-z0-9_]*)/
    |> Regex.scan(contents)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
  end

  defp with_hex_version(pkg, hex_lookup) do
    case hex_lookup.(pkg.name) do
      {:ok, version} -> Map.put(pkg, :hex_version, version)
      :not_found -> Map.put(pkg, :hex_version, nil)
      {:error, reason} -> Mix.raise("Hex lookup for #{pkg.name} failed: #{inspect(reason)}")
    end
  end

  defp needs_release?(%{version: local, hex_version: nil}) when is_binary(local), do: true

  defp needs_release?(%{version: local, hex_version: hex}) do
    Version.compare(local, hex) == :gt
  end

  # Kahn's algorithm. Edges go from dep → dependent (so deps come first).
  # Only edges into other releasables matter — if `:nbpr_libpcap` already
  # has a published version matching local, it's not a node here, and any
  # dependent (`:nbpr_tcpdump`) doesn't need to wait on it.
  defp topo_sort(releasables) do
    names = MapSet.new(releasables, & &1.name)

    in_edges =
      Map.new(releasables, fn pkg ->
        {pkg.name, MapSet.new(Enum.filter(pkg.deps, &MapSet.member?(names, &1)))}
      end)

    by_name = Map.new(releasables, &{&1.name, &1})

    do_topo(in_edges, by_name, [])
  end

  defp do_topo(in_edges, _by_name, _acc) when in_edges == %{}, do: []

  defp do_topo(in_edges, by_name, acc) do
    case Enum.filter(in_edges, fn {_, deps} -> MapSet.size(deps) == 0 end) do
      [] ->
        Mix.raise("cyclic dep graph in nbpr packages: #{inspect(Map.keys(in_edges))}")

      ready ->
        ready_names = ready |> Enum.map(&elem(&1, 0)) |> Enum.sort()

        new_in_edges =
          in_edges
          |> Map.drop(ready_names)
          |> Map.new(fn {name, deps} ->
            {name, Enum.reduce(ready_names, deps, &MapSet.delete(&2, &1))}
          end)

        emitted = Enum.map(ready_names, &Map.fetch!(by_name, &1))

        if new_in_edges == %{} do
          acc ++ emitted
        else
          do_topo(new_in_edges, by_name, acc ++ emitted)
        end
    end
  end

  defp print_human([]), do: Mix.shell().info("nothing to release.")

  defp print_human(entries) do
    Mix.shell().info("Releasable packages (in publish order):")

    Enum.each(entries, fn e ->
      current = e.hex_version || "—"
      Mix.shell().info("  #{e.tag}  (current on Hex: #{current})")
    end)
  end

  # Hex's org API returns the package as JSON with a `releases` array; the
  # latest stable lives at `latest_stable_version` (falling back to
  # `latest_version` for pre-1.0 packages without a stable release).
  defp fetch_hex_version(name) do
    key = System.get_env("NBPR_READ_KEY")

    if key in [nil, ""] do
      Mix.raise("NBPR_READ_KEY env var is required for Hex org lookups")
    end

    url = String.to_charlist("https://hex.pm/api/repos/#{@hex_org}/packages/#{name}")

    headers = [
      {~c"authorization", String.to_charlist(key)},
      {~c"accept", ~c"application/json"},
      {~c"user-agent", ~c"nbpr-releasable/1"}
    ]

    case :httpc.request(:get, {url, headers}, [], body_format: :binary) do
      {:ok, {{_, 200, _}, _, body}} ->
        case :json.decode(body) do
          %{"latest_stable_version" => v} when is_binary(v) -> {:ok, v}
          %{"latest_version" => v} when is_binary(v) -> {:ok, v}
          %{"releases" => [%{"version" => v} | _]} when is_binary(v) -> {:ok, v}
          _ -> {:error, :no_version_in_response}
        end

      {:ok, {{_, 404, _}, _, _}} ->
        :not_found

      {:ok, {{_, status, _}, _, body}} ->
        {:error, {:hex_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
