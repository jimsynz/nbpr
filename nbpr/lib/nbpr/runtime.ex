defmodule NBPR.Runtime do
  @moduledoc """
  Runtime helpers for Application-bearing NBPR packages.

  The generated `NBPR.<Name>.Application` module calls into here to decide
  whether to load kernel modules and how. Keeping these as plain functions
  in a stable module means: the codegen stays trivial, behaviour can be
  changed centrally without rebuilding every package, and tests can target
  the helpers directly.
  """

  @nerves_marker "/etc/nerves-system"

  @doc """
  Returns `true` when the current process is running on a Nerves target.

  Used to gate kernel-module loading so `mix test` and dev workflows on
  macOS/Linux are unaffected by package Applications.
  """
  @spec on_nerves_target?() :: boolean()
  def on_nerves_target? do
    File.exists?(@nerves_marker)
  end

  @doc """
  Runs `modprobe <name>` and raises on failure.

  modprobe is idempotent (re-loading an already-loaded module is fine) and
  resolves its own dependency graph from `modules.dep`, so transitive kernel
  modules don't need to be loaded explicitly.
  """
  @spec modprobe!(String.t()) :: :ok
  def modprobe!(name) when is_binary(name) do
    unless System.find_executable("modprobe") do
      raise "modprobe #{name} failed: modprobe binary not found on PATH"
    end

    case System.cmd("modprobe", [name], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, code} ->
        raise "modprobe #{name} failed (exit #{code}): #{String.trim(output)}"
    end
  end
end
