defmodule Mix.Tasks.Nbpr.Inspect do
  @shortdoc "Print metadata for an NBPR package"

  @moduledoc """
  Pretty-prints the `NBPR.Package` metadata struct for the given module.

      mix nbpr.inspect NBPR.Jq

  The argument must be a module that does `use NBPR.BrPackage`.
  """

  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run([]) do
    Mix.raise("usage: mix nbpr.inspect <Module>")
  end

  def run([module_name | _]) do
    module = Module.concat([module_name])

    unless Code.ensure_loaded?(module) and function_exported?(module, :__nbpr_package__, 0) do
      Mix.raise(
        "#{inspect(module)} is not an NBPR package (no `__nbpr_package__/0` callback). " <>
          "Did you forget `use NBPR.BrPackage`?"
      )
    end

    module.__nbpr_package__()
    |> NBPR.Inspector.format()
    |> IO.puts()
  end
end
