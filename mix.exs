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

      # Systems to source-build against. Add more as packages need them.
      {:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4},
      {:nerves_system_x86_64, "~> 1.13", runtime: false, targets: :x86_64}
    ] ++ package_deps()
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
