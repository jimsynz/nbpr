defmodule Nbpr.DockerCompose.MixProject do
  use Mix.Project

  @version "2.38.2"

  def project do
    [
      app: :nbpr_docker_compose,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Multi-container applications with the Docker CLI.",
      package: [
        organization: "nbpr",
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => "https://github.com/jimsynz/nbpr", "docker-compose" => "https://github.com/docker/compose"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      nbpr_dep(:nbpr, "~> 0.2"),
      nbpr_dep(:nbpr_docker_cli, "~> 28.0")
    ]
  end

  # Path dep for local dev (sibling in the workspace); Hex requirement
  # when publishing. Hex publish forbids path deps, so we switch the
  # spec only when the workflow asks for it. `:nbpr` itself lives on
  # public hex.pm; `:nbpr_*` packages live in the `nbpr` Hex org.
  defp nbpr_dep(:nbpr = name, requirement) do
    case System.get_env("NBPR_RELEASE") do
      "1" -> {name, requirement}
      _ -> {name, path: nbpr_dep_path(name)}
    end
  end

  defp nbpr_dep(name, requirement) do
    case System.get_env("NBPR_RELEASE") do
      "1" -> {name, requirement, organization: "nbpr"}
      _ -> {name, path: nbpr_dep_path(name)}
    end
  end

  defp nbpr_dep_path(:nbpr), do: "../../nbpr"
  defp nbpr_dep_path(name) when is_atom(name), do: "../" <> Atom.to_string(name)
end
