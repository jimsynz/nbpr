defmodule NBPR.Buildroot.Backend.Podman do
  @moduledoc """
  Buildroot backend that runs the build inside Podman.

  Podman is CLI-compatible with Docker for the `run`/`-v`/`-e`/`--user` subset
  the build uses, so it delegates to the shared `NBPR.Buildroot.Backend.Container`
  runner. The one difference is the output chown: see `rootless?/0`.
  """

  @behaviour NBPR.Buildroot.Backend

  alias NBPR.Buildroot.Backend.Container

  @executable "podman"

  @impl true
  def available?, do: Container.available?(@executable)

  @impl true
  def build!(spec),
    do: Container.build!(spec, executable: @executable, chown_output?: not rootless?())

  # Rootless podman maps container-uid-0 to the invoking host user, so files the
  # build writes to a bind mount are already host-owned — and a `chown` to the
  # host uid would instead resolve into the subuid range and make them
  # unreadable. Detecting this lets the build script skip that chown. Rootful
  # podman runs the container as real root, so it still needs it.
  #
  # If `info` fails, assume rootless — it's the safe default (skipping the chown
  # leaves host-owned files; an erroneous chown does not).
  defp rootless? do
    case System.cmd(@executable, ["info", "--format", "{{.Host.Security.Rootless}}"],
           stderr_to_stdout: true
         ) do
      {out, 0} -> String.trim(out) == "true"
      _ -> true
    end
  end
end
