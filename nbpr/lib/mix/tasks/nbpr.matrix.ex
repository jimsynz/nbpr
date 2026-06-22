defmodule Mix.Tasks.Nbpr.Matrix do
  @shortdoc "Emit the (package × target × system_version) prebuild matrix"

  @moduledoc """
  Generates the prebuild matrix for CI: every combination of an `nbpr_*`
  package under `packages/` with a target system declared in the workspace
  `mix.exs` `@prebuild_systems` map.

      mix nbpr.matrix [--json] [--root <path>]

  ## Kernel packages are excluded

  Kernel-replacement packages (`kind: :kernel`, e.g. `nbpr_linux`) are skipped.
  Their artefact depends on the consuming project's own config fragments and
  patches, so there's no shareable prebuilt to build or publish — they're
  always source-built in the project that uses them.

  ## Output

  Without flags: human-readable lines, one per matrix entry.

  With `--json`: a single line of GitHub Actions matrix JSON, ready to
  feed into a job's `strategy.matrix` via dynamic-matrix:

      jobs:
        generate:
          outputs:
            matrix: ${{ steps.gen.outputs.matrix }}
          steps:
            - id: gen
              run: echo "matrix=$(mix nbpr.matrix --json)" >> "$GITHUB_OUTPUT"

        build:
          needs: generate
          strategy:
            matrix: ${{ fromJson(needs.generate.outputs.matrix) }}
          steps:
            - run: MIX_TARGET=${{ matrix.target }} mix nbpr.build ${{ matrix.module }} -o out/

  ## Flags

    * `--json` — emit `{"include": [...]}` JSON suitable for GHA dynamic matrix
    * `--root <path>` — workspace root (defaults to current directory). Useful
      when running this task from a script that doesn't `cd` first.
  """

  use Mix.Task

  @switches [json: :boolean, root: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    root = opts[:root] || File.cwd!()
    entries = build_entries!(root)

    if opts[:json] do
      Mix.shell().info(:json.encode(%{include: entries}) |> IO.iodata_to_binary())
    else
      Enum.each(entries, fn e ->
        Mix.shell().info(
          "#{e.package}\tmodule=#{e.module}\ttarget=#{e.target}\tsystem_version=#{e.system_version}"
        )
      end)
    end
  end

  @doc false
  @spec build_entries!(Path.t()) :: [
          %{
            package: String.t(),
            module: String.t(),
            target: String.t(),
            system_version: String.t()
          }
        ]
  def build_entries!(root) do
    systems = prebuild_systems!(root)
    packages = discover_packages!(root)

    for package <- packages,
        {target, _github, version} <- systems do
      %{
        package: package,
        module: module_for(package),
        target: Atom.to_string(target),
        system_version: version
      }
    end
  end

  @doc false
  @spec module_for(String.t()) :: String.t()
  def module_for("nbpr_" <> short) do
    "NBPR." <> Macro.camelize(short)
  end

  defp discover_packages!(root) do
    root
    |> Path.join("packages/nbpr_*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
    |> case do
      [] -> Mix.raise("no `packages/nbpr_*` directories found under #{root}")
      pkgs -> Enum.reject(pkgs, &kernel_package?/1)
    end
  end

  @doc false
  # Kernel packages have no shareable prebuilt (the artefact is keyed on the
  # consuming project's config), so they don't belong in the publish matrix.
  # Reads the package's declared `:kind`; defaults to "included" if the module
  # can't be loaded, so a build issue never silently drops a userspace package.
  @spec kernel_package?(String.t()) :: boolean()
  def kernel_package?(package) do
    module = Module.concat([module_for(package)])

    Code.ensure_loaded?(module) and
      function_exported?(module, :__nbpr_package__, 0) and
      module.__nbpr_package__().kind == :kernel
  end

  defp prebuild_systems!(root) do
    case Mix.Project.get() do
      nil ->
        Mix.raise("no Mix project loaded; run from the workspace root")

      mod ->
        if function_exported?(mod, :prebuild_systems, 0) do
          mod.prebuild_systems()
        else
          Mix.raise(
            "Mix project at #{root} does not export `prebuild_systems/0`; " <>
              "add `@prebuild_systems` and the helper to mix.exs"
          )
        end
    end
  end
end
