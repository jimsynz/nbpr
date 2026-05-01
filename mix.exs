defmodule NBPR.Workspace.MixProject do
  @moduledoc """
  Workspace-level Mix project — the build harness for source-building nbpr
  packages.

  This is *not* the `:nbpr` library (that lives at `nbpr/`) and *not* a
  user-facing Nerves project. It exists so that `mix nbpr.build` has a
  Nerves-aware project context to run in: Nerves itself, the system(s)
  we're targeting, and every `nbpr_*` package as a path dep.

  Run from this directory:

      MIX_TARGET=rpi4 mix deps.get
      MIX_TARGET=rpi4 mix nbpr.build NBPR.Jq -o /tmp/jq-built
  """
  use Mix.Project

  # Pinned nerves_system_* versions. The git tag is `v<version>`, and the
  # version is what `Application.spec(:nerves_system_*, :vsn)` returns at
  # build time → it becomes part of the artefact's cache key. Bumping
  # any of these *will* invalidate prebuilt artefacts on GHCR for that
  # (package, system) combination, since the system_version component of
  # the cache key changes.
  #
  # Single source of truth for the CI prebuild matrix
  # (`mix nbpr.matrix --json`). Map shape: `target => {github, version}`.
  @prebuild_systems %{
    rpi4: {"nerves-project/nerves_system_rpi4", "2.0.2"},
    bbb: {"nerves-project/nerves_system_bbb", "2.29.2"}
  }

  @doc """
  Returns the prebuild matrix as a list of `{target, github, version}` tuples.
  Used by `mix nbpr.matrix` to emit the GHA dynamic matrix.
  """
  def prebuild_systems do
    for {target, {github, version}} <- @prebuild_systems,
        do: {target, github, version}
  end

  def project do
    [
      app: :nbpr_workspace,
      version: "0.0.0",
      elixir: "~> 1.16",
      archives: [nerves_bootstrap: "~> 1.15"],
      deps: deps()
    ]
  end

  def cli do
    [preferred_targets: [run: :host, test: :host]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    base = [
      # The :nbpr library + its tasks
      {:nbpr, path: "nbpr"},

      # Nerves itself, so Nerves.Env resolves the active system
      {:nerves, "~> 1.14", runtime: false}
    ]

    # `MIX_TARGET` selects exactly one system. Only that system's git pin is
    # in the dep tree — different systems pin different `nerves_system_br`
    # versions, so resolving multiple at once would conflict. Build all
    # supported targets in CI by re-running `mix deps.get && mix nbpr.build`
    # under each `MIX_TARGET=<target>`.
    base ++ system_dep_for(Mix.target()) ++ package_deps()
  end

  defp system_dep_for(:host), do: []

  defp system_dep_for(target) do
    case Map.fetch(@prebuild_systems, target) do
      {:ok, {github, version}} ->
        app = String.to_atom("nerves_system_#{target}")
        [{app, github: github, tag: "v#{version}", runtime: false, targets: target}]

      :error ->
        Mix.raise(
          "no `@prebuild_systems` entry for target #{inspect(target)}; " <>
            "add one to mix.exs to enable building against it"
        )
    end
  end

  # Auto-discover every `packages/nbpr_*/` and add it as a path dep so
  # `NBPR.<Camel>` modules are loadable from the workspace context.
  defp package_deps do
    "packages/*"
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(fn dir ->
      app = dir |> Path.basename() |> String.to_atom()
      {app, path: dir, runtime: false}
    end)
  end
end
