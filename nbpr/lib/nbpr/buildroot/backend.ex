defmodule NBPR.Buildroot.Backend do
  @moduledoc """
  Behaviour for the different ways NBPR can produce a per-package Buildroot
  artefact.

  A backend takes a `t:spec/0` (patched BR tree, output dir, rendered defconfig,
  BR package name, build env, extra mounts) and returns the *harvest dir* — the
  directory containing `per-package/<br_package>/{target,staging,legal-info}`,
  ready for `NBPR.Buildroot.Harvest.harvest!/2`.

  Current backends, tried in order by `select/0`:

    - `NBPR.Buildroot.Backend.Shell` — native `make` on the host. Only usable
      inside the Nerves canonical build env (`mix nerves.system.shell`), where
      the toolchain wrappers, sysroot paths, and ABI flags already match.
    - `NBPR.Buildroot.Backend.Docker` / `NBPR.Buildroot.Backend.Podman` — run
      the build inside `ghcr.io/nerves-project/nerves_system_br:latest` via a
      shared container runner (`NBPR.Buildroot.Backend.Container`). This is the
      everywhere-else path, including non-Linux hosts.

  Adding a new style of builder (e.g. Apple's `container`, a Windows runtime) is
  a matter of implementing this behaviour and listing it in `@backends`.

  ## Overriding the choice

  Set `NBPR_BUILD_BACKEND` to a backend's short name (`shell`, `docker`,
  `podman`) to force that backend, bypassing the auto-detect ordering. This is
  handy when more than one runtime is present (e.g. force `podman` when `docker`
  would otherwise win) or to force a native build outside the canonical env. The
  chosen backend's `build!/1` still fails loudly if it genuinely can't run.
  """

  alias NBPR.Buildroot.Backend.{Docker, Podman, Shell}

  @type spec :: %{
          br_source: Path.t(),
          output_dir: Path.t(),
          defconfig_text: String.t(),
          br_package: String.t(),
          env: [{String.t(), String.t()}],
          extra_mounts: [Path.t()]
        }

  @doc "Whether this backend can run in the current environment."
  @callback available?() :: boolean()

  @doc """
  Builds the artefact described by `spec` and returns the harvest dir
  (containing `per-package/<br_package>/`).
  """
  @callback build!(spec()) :: Path.t()

  # Order is precedence: Shell wins inside the canonical env (no point nesting a
  # container), otherwise the first available container runtime is used.
  @backends [Shell, Docker, Podman]

  @env_var "NBPR_BUILD_BACKEND"

  @doc """
  Returns the backend to use.

  Honours a `NBPR_BUILD_BACKEND` override if set (see the module docs);
  otherwise returns the first backend that can run in the current environment.
  Raises with guidance if the override is unknown or no backend is available.
  """
  @spec select() :: module()
  def select do
    case System.get_env(@env_var) do
      name when name in [nil, ""] -> auto_select()
      name -> forced_backend!(name)
    end
  end

  defp auto_select do
    Enum.find(@backends, & &1.available?()) || raise no_backend_message()
  end

  defp forced_backend!(name) do
    Enum.find(@backends, &(backend_name(&1) == name)) ||
      raise """
      Unknown #{@env_var}=#{inspect(name)}. Valid backends: \
      #{@backends |> Enum.map(&backend_name/1) |> Enum.join(", ")}.
      """
  end

  defp backend_name(backend) do
    backend |> Module.split() |> List.last() |> Macro.underscore()
  end

  defp no_backend_message do
    """
    No usable Buildroot backend found. `mix nbpr.build` needs one of:

      - to be run from inside `mix nerves.system.shell` (native build), or
      - `docker` or `podman` on PATH (containerised build, any host), or
      - `IN_NERVES_DEV_SHELL=1` set if you're confident the host env matches
        the canonical Nerves build container.
    """
  end
end
