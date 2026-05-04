defmodule Mix.Tasks.Nbpr.Catalogue do
  @shortdoc "Generate docs/reference/catalogue.md from the workspace's packages/"

  @moduledoc """
  Refreshes `docs/reference/catalogue.md` by globbing the workspace's
  `packages/nbpr_*/` directories and reading each package's `mix.exs`
  for the version and description.

  No network access — the workspace itself is the source of truth.
  Retired or legacy packages aren't in the workspace, so they're
  naturally excluded.

      mix nbpr.catalogue [--root <path>] [--output <path>]

  Wired up via the `docs:` alias in `nbpr/mix.exs`, so `mix docs`
  always generates a fresh catalogue before ExDoc renders.

  ## Flags

    * `--root <path>` — workspace root (defaults to the parent of the
      current directory, i.e. correct when invoked from `nbpr/`).
    * `--output <path>` — where to write the catalogue (defaults to
      `<root>/docs/reference/catalogue.md`).
  """

  use Mix.Task

  @switches [root: :string, output: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    root = opts[:root] || Path.expand("..")
    output = opts[:output] || Path.join([root, "docs", "reference", "catalogue.md"])

    pkgs = scan_packages(root)
    md = catalogue_markdown(pkgs)

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, md)

    Mix.shell().info("Wrote #{Path.relative_to_cwd(output)} (#{length(pkgs)} packages)")
  end

  @doc """
  Renders the catalogue markdown for `pkgs`. Public for testability.

  Each entry in `pkgs` is a `%{name, version, description}` map.
  """
  @spec catalogue_markdown([%{name: String.t(), version: String.t(), description: String.t()}]) ::
          String.t()
  def catalogue_markdown(pkgs) do
    """
    # Catalogue

    The current set of binary packages in the `nbpr` Hex organisation,
    derived from `packages/` in the workspace at docs-build time.

    The `:nbpr` library itself isn't shown — it lives on public
    hex.pm rather than the `nbpr` organisation. Install it directly
    from [hex.pm/packages/nbpr](https://hex.pm/packages/nbpr).

    #{render_table(pkgs)}

    ## Using a package

    Add the library plus whichever binary packages you need:

    ```elixir
    defp deps do
      [
        {:nbpr, "~> 0.2"},
        {:nbpr_jq, "~> 1.0", organization: "nbpr"}
      ]
    end
    ```

    See [Getting started](getting-started.md) for the full consumer
    flow, including authenticating to the `nbpr` organisation.
    """
  end

  defp scan_packages(root) do
    root
    |> Path.join("packages/nbpr_*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.sort()
    |> Enum.map(&read_package/1)
  end

  defp read_package(dir) do
    name = Path.basename(dir)
    contents = dir |> Path.join("mix.exs") |> File.read!()

    %{
      name: name,
      version: extract(contents, ~r/@version\s+"([^"]+)"/),
      description: extract(contents, ~r/description:\s+"([^"]+)"/)
    }
  end

  defp extract(contents, regex) do
    case Regex.run(regex, contents) do
      [_, value] -> value
      _ -> ""
    end
  end

  defp render_table([]) do
    "_No packages in the workspace yet._"
  end

  defp render_table(pkgs) do
    header = "| Package | Version | Description |\n| --- | --- | --- |"
    rows = Enum.map_join(pkgs, "\n", &render_row/1)
    "#{header}\n#{rows}"
  end

  defp render_row(%{name: name, version: version, description: description}) do
    url = "https://hex.pm/packages/nbpr/#{name}"
    "| [`:#{name}`](#{url}) | #{version} | #{escape_pipes(description)} |"
  end

  defp escape_pipes(s), do: String.replace(s, "|", "\\|")
end
