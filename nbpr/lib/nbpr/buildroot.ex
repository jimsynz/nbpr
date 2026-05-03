defmodule NBPR.Buildroot do
  @moduledoc """
  Discovery helpers for building nbpr packages against the user's pinned
  Buildroot tree.

  After `mix deps.get`, the user's project contains `deps/nerves_system_br/`
  with everything we need to drive a per-package Buildroot build:

  - `create-build.sh` — pins `NERVES_BR_VERSION=<version>` (e.g. `2025.11.3`)
  - `scripts/download-buildroot.sh` — fetches the BR tarball from upstream
  - `patches/buildroot/` — Nerves-specific patches that must be applied
    before building anything against this BR tree (otherwise nbpr packages
    will build against an incompatible upstream BR and may fail at runtime)
  - `external.desc`, `external.mk`, `Config.in`, `package/` — Nerves' BR
    external tree, exposing extra packages and the `nerves` toolchain hooks

  This module reads what's needed from there. Actual build invocation lives
  in subsequent modules.
  """

  @doc """
  Returns the absolute path to `deps/nerves_system_br/` in the active Mix
  project's deps tree, or `{:error, :not_found}` if it isn't a dep.

  Use `nerves_system_br_path/1` when the lookup needs to span a different
  Mix project (e.g. a generator running inside the `:nbpr` library that
  needs to locate the *workspace's* `nerves_system_br`).
  """
  @spec nerves_system_br_path() :: {:ok, Path.t()} | {:error, :not_found}
  def nerves_system_br_path do
    nerves_system_br_path(Mix.Project.deps_path())
  end

  @doc """
  Returns the absolute path to `nerves_system_br/` under `deps_path`, or
  `{:error, :not_found}` if absent.
  """
  @spec nerves_system_br_path(Path.t()) :: {:ok, Path.t()} | {:error, :not_found}
  def nerves_system_br_path(deps_path) do
    candidate = Path.join(deps_path, "nerves_system_br")

    if File.dir?(candidate) do
      {:ok, candidate}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Reads the pinned `NERVES_BR_VERSION` from `nerves_system_br`'s
  `create-build.sh`. The returned string is the upstream Buildroot release
  identifier, e.g. `"2025.11.3"`.
  """
  @spec br_version(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def br_version(nerves_system_br_path) do
    create_build = Path.join(nerves_system_br_path, "create-build.sh")

    with {:ok, content} <- File.read(create_build) do
      case Regex.run(~r/^NERVES_BR_VERSION=([0-9.]+)/m, content) do
        [_, version] -> {:ok, version}
        _ -> {:error, :br_version_not_found_in_create_build_sh}
      end
    end
  end

  @doc """
  Returns the path to `nerves_system_br`'s buildroot patch directory, or
  `{:error, :not_found}` if absent. These patches must be applied to the
  upstream BR tree before any build.
  """
  @spec patches_path(Path.t()) :: {:ok, Path.t()} | {:error, :not_found}
  def patches_path(nerves_system_br_path) do
    candidate = Path.join([nerves_system_br_path, "patches", "buildroot"])

    if File.dir?(candidate) do
      {:ok, candidate}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Lists the patch filenames (relative to `patches_path/1`) in the order
  Buildroot's patch script expects them — sorted lexicographically, which
  matches the leading numeric prefix convention (`0001-...`, `0002-...`).
  """
  @spec patch_files(Path.t()) :: [String.t()]
  def patch_files(patches_dir) do
    patches_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".patch"))
    |> Enum.sort()
  end
end
