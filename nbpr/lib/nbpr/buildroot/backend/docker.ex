defmodule NBPR.Buildroot.Backend.Docker do
  @moduledoc """
  Buildroot backend that runs the build inside Docker.

  Docker runs the container as real root, so the extracted output is root-owned
  on the host and must be chowned back to the invoking user. Everything else is
  handled by the shared `NBPR.Buildroot.Backend.Container` runner.
  """

  @behaviour NBPR.Buildroot.Backend

  alias NBPR.Buildroot.Backend.Container

  @executable "docker"

  @impl true
  def available?, do: Container.available?(@executable)

  @impl true
  def build!(spec), do: Container.build!(spec, executable: @executable, chown_output?: true)
end
