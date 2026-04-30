defmodule NBPR.Artifact do
  @moduledoc """
  Cache-key, naming, and on-disk layout for NBPR package artefacts.

  An nbpr artefact is a tarball produced by source-building a Buildroot
  package against a specific (system, system-version, build-options) tuple.
  This module is the single source of truth for:

  - the canonical cache key derived from those inputs
  - the canonical tarball filename
  - the local cache directory where the extracted tree lives

  Tarball layout (matches `Nerves.Artifact.Archive`'s `--strip-components=1`
  contract so we can reuse its extractor later):

      <package>-<version>-<system>-<system_version>/
        manifest.json
        target/         # rootfs overlay
        staging/        # sysroot overlay (optional)
        legal-info/

  All functions here are pure. I/O lives in `Mix.Tasks.Nbpr.Fetch` and the
  resolver implementations.
  """

  @type build_inputs :: %{
          required(:package_name) => String.t(),
          required(:package_version) => String.t(),
          required(:system_app) => atom(),
          required(:system_version) => String.t(),
          required(:build_opts) => keyword()
        }

  @cache_key_length 16

  @doc """
  Returns a 16-character hex digest derived from a SHA-256 over the canonical
  encoding of all inputs. The encoding sorts `build_opts` so that opt order
  doesn't perturb the key.
  """
  @spec cache_key(build_inputs()) :: String.t()
  def cache_key(%{} = inputs) do
    :sha256
    |> :crypto.hash(canonical_encode(inputs))
    |> Base.encode16(case: :lower)
    |> String.slice(0, @cache_key_length)
  end

  @doc """
  Returns the canonical tarball filename for a given set of build inputs.

      "nbpr_jq-0.1.0-nerves_system_rpi4-1.30.0-<key>.tar.gz"
  """
  @spec tarball_name(build_inputs()) :: String.t()
  def tarball_name(%{} = inputs) do
    "#{tarball_stem(inputs)}.tar.gz"
  end

  @doc """
  Returns the directory name (no leading path) where the extracted artefact
  will live. This is also the single top-level directory expected inside the
  tarball.
  """
  @spec dir_name(build_inputs()) :: String.t()
  def dir_name(%{} = inputs), do: tarball_stem(inputs)

  @doc """
  Returns the absolute path to the extracted artefact directory under the
  Nerves data dir. Mirrors `Nerves.Env.data_dir/0`'s behaviour: respects
  `NERVES_ARTIFACTS_DIR`, falls back to `$XDG_DATA_HOME/nerves`, then
  `~/.local/share/nerves`.
  """
  @spec cache_dir(build_inputs()) :: String.t()
  def cache_dir(%{} = inputs) do
    Path.join([data_dir(), "nbpr", dir_name(inputs)])
  end

  @doc """
  Returns the absolute path where the downloaded tarball is staged before
  extraction. Sibling to the artefacts dir, mirroring Nerves' `dl/` convention.
  """
  @spec download_path(build_inputs()) :: String.t()
  def download_path(%{} = inputs) do
    Path.join([data_dir(), "nbpr", "dl", tarball_name(inputs)])
  end

  @doc """
  Returns a JSON-serialisable map describing the artefact for inclusion as
  `manifest.json` inside the tarball. Lets consumers verify that an extracted
  artefact matches the cache key they expected.
  """
  @spec manifest(build_inputs()) :: map()
  def manifest(%{} = inputs) do
    %{
      "package_name" => inputs.package_name,
      "package_version" => inputs.package_version,
      "system_app" => Atom.to_string(inputs.system_app),
      "system_version" => inputs.system_version,
      "build_opts" => Map.new(inputs.build_opts, fn {k, v} -> {Atom.to_string(k), v} end),
      "cache_key" => cache_key(inputs),
      "schema_version" => 1
    }
  end

  defp tarball_stem(inputs) do
    "#{inputs.package_name}-#{inputs.package_version}-" <>
      "#{inputs.system_app}-#{inputs.system_version}-#{cache_key(inputs)}"
  end

  defp canonical_encode(inputs) do
    [
      inputs.package_name,
      inputs.package_version,
      Atom.to_string(inputs.system_app),
      inputs.system_version,
      canonical_build_opts(inputs.build_opts)
    ]
    |> Enum.join("\x00")
  end

  defp canonical_build_opts(opts) do
    opts
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
    |> Enum.join(",")
  end

  defp data_dir do
    cond do
      dir = System.get_env("NERVES_ARTIFACTS_DIR") ->
        dir

      true ->
        base = System.get_env("XDG_DATA_HOME") || Path.join(System.user_home!(), ".local/share")
        Path.join(base, "nerves")
    end
  end
end
