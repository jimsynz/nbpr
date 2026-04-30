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
  @system_versions %{
    rpi4: "2.0.2"
  }

  def project do
    [
      app: :nbpr_workspace,
      version: "0.0.0",
      elixir: "~> 1.16",
      archives: [nerves_bootstrap: "~> 1.15"],
      deps: deps(),
      preferred_cli_target: [run: :host, test: :host]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # The :nbpr library + its tasks
      {:nbpr, path: "nbpr"},

      # Nerves itself, so Nerves.Env resolves the active system
      {:nerves, "~> 1.14", runtime: false},

      # Systems to source-build against. We pull these from GitHub rather
      # than Hex because the Hex tarballs deliberately exclude Config.in
      # and patches/ (Hex users consume the prebuilt artefact, not source).
      #
      # Adding a new target system requires its `nerves_system_br` pin to
      # match the others. As of this writing rpi4 v2.0.2 → nerves_system_br
      # 1.33.5; older systems (e.g. x86_64 v1.13.0 → 1.13.x) are
      # incompatible until they're bumped.
      system_dep(:rpi4, "nerves-project/nerves_system_rpi4")
    ] ++ package_deps()
  end

  defp system_dep(target, github) do
    version = Map.fetch!(@system_versions, target)
    app = String.to_atom("nerves_system_#{target}")

    {app, github: github, tag: "v#{version}", runtime: false, targets: target}
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
