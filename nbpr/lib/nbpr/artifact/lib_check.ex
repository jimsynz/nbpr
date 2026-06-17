defmodule NBPR.Artifact.LibCheck do
  @moduledoc """
  Firmware-time shared-library resolution check.

  After `mix nbpr.fetch` stages every nbpr package into its `priv/`, this finds
  `DT_NEEDED` shared libraries that a package's binaries link against but that
  nothing in the assembled firmware provides — surfacing the whole list in one
  build instead of one missing `.so` per device boot.

  "Provided" is resolved exactly as the dynamic loader would: a soname is
  satisfied if a file of that name exists on the runtime library path. That
  path is the union of:

    * the base system's libraries (`<system>/staging/{lib,usr/lib,...}`), and
    * every nbpr package's own `priv/{usr/lib,lib}` — `NBPR.Application`
      prepends these to `LD_LIBRARY_PATH` at boot, so a library shipped by a
      sibling nbpr package counts as provided.

  So the check is firmware-wide: a soname `nbpr_cryptsetup` needs from
  `nbpr_popt` resolves as long as `nbpr_popt` is also in the firmware.
  """

  alias NBPR.Elf

  @priv_lib_subdirs ~w(usr/lib lib)
  @system_lib_subdirs ~w(lib usr/lib lib32 usr/lib32)

  @doc """
  Returns `[{app, [missing_soname]}]` for staged packages with at least one
  unresolved `DT_NEEDED`. Empty list when everything resolves.

  `base_lib_dirs` are the base system's library directories; `packages` is a
  list of `{app, priv_dir}` for the staged nbpr packages.
  """
  @spec missing([Path.t()], [{atom(), Path.t()}]) :: [{atom(), [String.t()]}]
  def missing(base_lib_dirs, packages) do
    provided =
      provided_sonames(
        base_lib_dirs ++ Enum.flat_map(packages, fn {_app, priv} -> lib_dirs(priv) end)
      )

    packages
    |> Enum.map(fn {app, priv} -> {app, required_sonames(priv)} end)
    |> unresolved(provided)
  end

  @doc """
  The set of soname filenames present across `dirs` — the dynamic loader's
  notion of "provided".
  """
  @spec provided_sonames([Path.t()]) :: MapSet.t()
  def provided_sonames(dirs) do
    for dir <- dirs,
        File.dir?(dir),
        entry <- File.ls!(dir),
        String.contains?(entry, ".so"),
        into: MapSet.new(),
        do: entry
  end

  @doc """
  Pure diff: given each package's required sonames and the provided set,
  returns `[{app, sorted_missing}]` for packages with anything unresolved.
  """
  @spec unresolved([{atom(), [String.t()]}], MapSet.t()) :: [{atom(), [String.t()]}]
  def unresolved(required_by_app, provided) do
    required_by_app
    |> Enum.map(fn {app, needed} ->
      {app, needed |> Enum.uniq() |> Enum.reject(&MapSet.member?(provided, &1)) |> Enum.sort()}
    end)
    |> Enum.reject(fn {_app, missing} -> missing == [] end)
  end

  @doc """
  The base system's existing library directories under `system_path`'s
  `staging/` tree, or `[]` when `system_path` is `nil` or none exist.
  """
  @spec base_lib_dirs(Path.t() | nil) :: [Path.t()]
  def base_lib_dirs(nil), do: []

  def base_lib_dirs(system_path) do
    for sub <- @system_lib_subdirs,
        dir = Path.join([system_path, "staging", sub]),
        File.dir?(dir),
        do: dir
  end

  defp required_sonames(priv) do
    priv
    |> elf_files()
    |> Enum.flat_map(&Elf.needed/1)
  end

  defp elf_files(priv) do
    priv
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.filter(&Elf.elf?/1)
  end

  defp lib_dirs(priv), do: Enum.map(@priv_lib_subdirs, &Path.join(priv, &1))
end
