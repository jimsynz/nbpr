defmodule Mix.Tasks.Nbpr.Matrix do
  @shortdoc "Emit the (package × target × system_version) prebuild matrix"

  @moduledoc """
  Generates the prebuild matrix for CI: combinations of an `nbpr_*` package
  under `packages/` with a target system declared in the workspace `mix.exs`
  `@prebuild_systems` map.

      mix nbpr.matrix [--json] [--changed-since <ref>] [--root <path>]

  ## Scoping by change

  Rebuilding an artefact whose cache key hasn't moved achieves nothing —
  `mix nbpr.publish` treats a published tarball as immutable and
  short-circuits — so CI passes `--changed-since <ref>` and gets only the
  work the diff implies:

    * a `packages/nbpr_<name>/` file changed — that package, every target.
      Its version or metadata moved, so every target's artefact is stale.
    * a `@prebuild_systems` pin in the workspace `mix.exs` changed — every
      package, but only the targets whose version moved. The system version
      is part of the cache key, so a bump invalidates that target's
      artefacts across the board and leaves every other target alone.
    * anything else that can change how a build runs — the `:nbpr`
      library's build path, this workflow — every package against
      `--default-target` only. Neither invalidates a cache key, so this is
      smoke coverage rather than a rebuild: broad across packages, one
      target deep.

  Not every library change qualifies. `nbpr/` holds tooling and runtime
  code that no Buildroot build can reach — the test suite, `mix.exs`, the
  `nbpr.new`/`nbpr.install`/`nbpr.inspect` family, the on-device runtime
  modules — and a change confined to those selects nothing. Anything else
  under `nbpr/` does earn smoke coverage, including files added later: an
  unrecognised module is assumed to matter, since over-building is
  recoverable where silently building nothing isn't.

  Entries are deduplicated, so a package that qualifies twice is built
  once per target.

  Without `--changed-since` the full cross-product is emitted, which is
  what `workflow_dispatch` wants for a deliberate from-scratch rebuild.

  ## GitHub's 256-configuration cap

  GitHub refuses to expand a *single job's* strategy past 256
  configurations. Two probes established what's actually enforced, since
  the documented "256 jobs per workflow run" isn't it:

    * two sibling jobs of 200 and 100 configurations expanded all 300 —
      so the cap is per strategy, not per run;
    * an outer matrix of 2 driving a reusable workflow with a 200-entry
      inner matrix expanded all 400 — so `strategy` is honoured on a
      `uses:` job, and each instantiated inner strategy gets its own
      budget.

  So `--slices` emits the outer half of a two-level matrix, one entry per
  target, each carrying its own inner matrix. Capacity becomes 256 targets
  × 256 packages instead of 256 in total, and adding packages never needs
  this revisited.

  `--max` still guards each slice, because an oversized strategy fails the
  run at strategy-evaluation time with no failing *check* to show for it:
  the run goes red while every check stays green and branch protection
  waves it through.

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

  An empty matrix is a legitimate result — a docs-only diff builds nothing.
  `{"include": []}` makes GitHub skip the job, so gate it on `--count`
  instead if the distinction matters to the workflow.

  ## Flags

    * `--json` — emit `{"include": [...]}` JSON suitable for GHA dynamic matrix
    * `--slices` — emit the outer matrix of a two-level fan-out: one entry
      per target, each carrying its target's inner matrix as a string. This
      is what CI feeds to `build-slice.yml`.
    * `--count` — emit just the number of entries, for a workflow that needs
      to know whether there's work before defining a job
    * `--changed-since <ref>` — scope to the work implied by
      `git diff <ref>...HEAD`, per the rules above
    * `--default-target <target>` — the target used for smoke coverage of
      library and workflow changes (defaults to `rpi4`)
    * `--target <target>` — restrict to one target
    * `--package <name>` — restrict to one package, with or without the
      `nbpr_` prefix
    * `--max <n>` — refuse to emit more than `n` entries (defaults to 256,
      GitHub's per-job cap). `0` disables the check. Failing here is the
      point: an oversized matrix makes GitHub fail the run at
      strategy-evaluation time, which produces no failing *check* and so
      doesn't block a merge.
    * `--root <path>` — workspace root (defaults to current directory). Useful
      when running this task from a script that doesn't `cd` first.
  """

  use Mix.Task

  # GitHub Actions refuses to expand a matrix beyond this many
  # configurations, and does it as a run-level error with no job attached —
  # invisible to branch protection. Better to fail here, in a job that
  # reports.
  @gha_matrix_limit 256

  @default_target "rpi4"

  # Matches the workspace `mix.exs` `@prebuild_systems` entries. Deliberately
  # the same shape Renovate's custom manager matches, so the two agree on
  # what a pin looks like.
  @system_pin_regex ~r/\{"nerves-project\/nerves_system_([A-Za-z0-9_]+)",\s*"([0-9]+(?:\.[0-9]+){1,2})"\}/

  # Paths under `nbpr/` that cannot reach a Buildroot build, and so earn no
  # smoke coverage: the library's own metadata and test suite, the tasks that
  # run outside a build, and the modules that only execute on a device. Named
  # individually rather than as an allowlist of the build path, because
  # anything unrecognised should still be assumed to matter — over-building is
  # recoverable, silently building nothing isn't.
  @inert_library_paths [
    ".formatter.exs",
    "README.md",
    "lib/mix/tasks/nbpr.cache.ex",
    "lib/mix/tasks/nbpr.catalogue.ex",
    "lib/mix/tasks/nbpr.inspect.ex",
    "lib/mix/tasks/nbpr.install.ex",
    "lib/mix/tasks/nbpr.matrix.ex",
    "lib/mix/tasks/nbpr.new.ex",
    "lib/mix/tasks/nbpr.releasable.ex",
    "lib/nbpr/application.ex",
    "lib/nbpr/inspector.ex",
    "lib/nbpr/package/daemon.ex",
    "lib/nbpr/runtime.ex",
    "mix.exs",
    "mix.lock"
  ]

  @switches [
    json: :boolean,
    slices: :boolean,
    count: :boolean,
    changed_since: :string,
    default_target: :string,
    target: :string,
    package: :string,
    max: :integer,
    root: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    root = opts[:root] || File.cwd!()
    entries = build_entries!(root, opts)

    cond do
      opts[:count] ->
        Mix.shell().info(to_string(length(entries)))

      opts[:slices] ->
        Mix.shell().info(IO.iodata_to_binary(:json.encode(%{include: slices(entries, opts)})))

      opts[:json] ->
        entries
        |> enforce_limit!(opts)
        |> then(&Mix.shell().info(IO.iodata_to_binary(:json.encode(%{include: &1}))))

      true ->
        Enum.each(entries, &Mix.shell().info(describe(&1)))
    end
  end

  @doc """
  Groups `entries` into one slice per target, each carrying its own inner
  matrix JSON as a string.

  This is the outer half of a two-level matrix. GitHub caps a *single job's*
  strategy at 256 configurations, but a reusable workflow called from a
  matrix'd job instantiates a fresh inner job with its own budget — verified
  by probe: an outer matrix of 2 driving an inner matrix of 200 expanded all
  400. So capacity multiplies rather than adds, and the cap stops being
  something this repo has to plan around.

  Slicing by target rather than by arbitrary shards means a slice is exactly
  one `(system, system_version)`, which is what a build job's caches are keyed
  on anyway. The inner matrix is embedded as a *string* deliberately: the
  workflow then reads `${{ matrix.matrix }}` straight out of the outer matrix
  context, with no JSON-object indexing in a `with:` block.
  """
  @spec slices([map()], keyword()) :: [map()]
  def slices(entries, opts \\ []) do
    entries
    |> Enum.group_by(& &1.target)
    |> Enum.sort_by(fn {target, _} -> target end)
    |> Enum.map(fn {target, slice} ->
      %{
        target: target,
        system_version: slice |> hd() |> Map.fetch!(:system_version),
        count: length(slice),
        matrix:
          slice
          |> enforce_limit!(opts)
          |> then(&IO.iodata_to_binary(:json.encode(%{include: &1})))
      }
    end)
  end

  @doc false
  @spec build_entries!(Path.t(), keyword()) :: [
          %{
            package: String.t(),
            module: String.t(),
            target: String.t(),
            system_version: String.t()
          }
        ]
  def build_entries!(root, opts \\ []) do
    systems = prebuild_systems!(root)
    packages = discover_packages!(root)

    packages
    |> full_cross_product(systems)
    |> scope_to_changes(root, packages, opts)
    |> restrict(:target, opts[:target])
    |> restrict(:package, normalise_package(opts[:package]))
  end

  @doc false
  @spec module_for(String.t()) :: String.t()
  def module_for("nbpr_" <> short) do
    "NBPR." <> Macro.camelize(short)
  end

  @doc """
  Filters `entries` down to the work implied by a diff. Pure, so the scoping
  rules are testable without a git repository.

  `changed_paths` are repo-relative paths. `changed_targets` are the targets
  whose `@prebuild_systems` pin moved. `default_target` carries the smoke
  coverage for changes that affect how builds run without invalidating any
  cache key.
  """
  @spec select([map()], [String.t()], [String.t()], String.t()) :: [map()]
  def select(entries, changed_paths, changed_targets, default_target) do
    changed_packages = changed_packages(changed_paths)
    smoke? = Enum.any?(changed_paths, &affects_builds?/1)

    entries
    |> Enum.filter(fn entry ->
      entry.package in changed_packages or
        entry.target in changed_targets or
        (smoke? and entry.target == default_target)
    end)
    |> Enum.uniq()
  end

  @doc """
  Returns the targets whose `@prebuild_systems` pin differs between two
  `mix.exs` texts — the set whose artefacts a version bump invalidated.
  """
  @spec changed_targets(String.t(), String.t()) :: [String.t()]
  def changed_targets(previous_mix_exs, current_mix_exs) do
    previous = system_pins(previous_mix_exs)

    current_mix_exs
    |> system_pins()
    |> Enum.reject(fn {target, version} -> Map.get(previous, target) == version end)
    |> Enum.map(fn {target, _version} -> target end)
    |> Enum.sort()
  end

  defp system_pins(mix_exs) do
    @system_pin_regex
    |> Regex.scan(mix_exs)
    |> Map.new(fn [_match, target, version] -> {target, version} end)
  end

  defp full_cross_product(packages, systems) do
    for package <- packages,
        {target, _github, version, libc} <- systems,
        supported?(package, libc) do
      %{
        package: package,
        module: module_for(package),
        target: Atom.to_string(target),
        system_version: version
      }
    end
  end

  # A package declaring `unsupported_libc:` is left out of those targets
  # entirely — the artefact can't be built, so a matrix entry for it is a job
  # that exists only to go red. A package whose module isn't loadable is kept:
  # the matrix shouldn't quietly drop work because introspection failed.
  defp supported?(package, libc) do
    module = Module.concat([module_for(package)])

    if Code.ensure_loaded?(module) and function_exported?(module, :__nbpr_package__, 0) do
      libc not in module.__nbpr_package__().unsupported_libc
    else
      true
    end
  end

  defp scope_to_changes(entries, root, packages, opts) do
    case opts[:changed_since] do
      nil ->
        entries

      ref ->
        default_target = opts[:default_target] || @default_target

        case changed_paths(root, ref) do
          {:ok, paths} ->
            select(entries, paths, targets_from_diff(root, ref, paths), default_target)

          :error ->
            # No usable diff (shallow clone, unrelated histories, a
            # zero-SHA `before` on a branch's first push). Build every
            # package on the default target rather than nothing: too much
            # work is recoverable, silently skipping the build isn't.
            Mix.shell().error(
              "[nbpr.matrix] could not diff against #{ref}; falling back to " <>
                "all #{length(packages)} packages on #{default_target}"
            )

            Enum.filter(entries, &(&1.target == default_target))
        end
    end
  end

  defp changed_paths(root, ref) do
    case System.cmd("git", ["-C", root, "diff", "--name-only", "#{ref}...HEAD"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)}
      _ -> :error
    end
  end

  defp targets_from_diff(root, ref, paths) do
    if "mix.exs" in paths do
      case System.cmd("git", ["-C", root, "show", "#{ref}:mix.exs"], stderr_to_stdout: true) do
        {previous, 0} -> changed_targets(previous, File.read!(Path.join(root, "mix.exs")))
        _ -> []
      end
    else
      []
    end
  end

  defp changed_packages(changed_paths) do
    for path <- changed_paths,
        ["packages", package | _rest] <- [Path.split(path)],
        String.starts_with?(package, "nbpr_"),
        uniq: true,
        do: package
  end

  # A change here can alter what a build produces without moving any cache
  # key, so it earns smoke coverage. Package directories are handled
  # separately, and everything else — docs, the release workflows, the test
  # workflow — has no bearing on a Buildroot build.
  #
  # `nbpr/` is where the judgement lives. Treating the whole library as
  # build-affecting fired smoke on version bumps, Renovate dep updates and
  # README edits, each fanning every package out to the default target for no
  # build-relevant reason.
  defp affects_builds?(".github/workflows/build.yml"), do: true
  defp affects_builds?("nbpr/" <> library_path), do: not inert?(library_path)
  defp affects_builds?(_path), do: false

  defp inert?("test/" <> _rest), do: true
  defp inert?(library_path), do: library_path in @inert_library_paths

  defp restrict(entries, _key, nil), do: entries

  defp restrict(entries, key, value) do
    case Enum.filter(entries, &(Map.fetch!(&1, key) == value)) do
      [] ->
        Mix.raise(
          "no matrix entries with #{key} #{inspect(value)}; " <>
            "known values: #{entries |> Enum.map(&Map.fetch!(&1, key)) |> Enum.uniq() |> Enum.sort() |> Enum.join(", ")}"
        )

      filtered ->
        filtered
    end
  end

  defp normalise_package(nil), do: nil
  defp normalise_package("nbpr_" <> _rest = package), do: package
  defp normalise_package(short), do: "nbpr_" <> short

  defp enforce_limit!(entries, opts) do
    max = Keyword.get(opts, :max, @gha_matrix_limit)

    if max > 0 and length(entries) > max do
      Mix.raise("""
      matrix has #{length(entries)} entries, over the limit of #{max}.

      GitHub Actions refuses to expand a matrix beyond #{@gha_matrix_limit}
      configurations, and reports it as a run-level error with no job
      attached — so the run fails while every *check* still passes, and
      branch protection waves it through.

      Narrow the matrix instead:

        --changed-since <ref>   only the work a diff implies
        --target <target>       one target at a time
        --package <name>        one package at a time

      Or pass `--max 0` if you genuinely want the whole list printed.
      """)
    end

    entries
  end

  defp describe(entry) do
    "#{entry.package}\tmodule=#{entry.module}\ttarget=#{entry.target}\tsystem_version=#{entry.system_version}"
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
      pkgs -> pkgs
    end
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
