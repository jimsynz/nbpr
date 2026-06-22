defmodule NBPR.Linux.Config do
  @moduledoc """
  Resolves a kernel package's extra configuration — Linux `.config` fragments
  and kernel source patches — from the user's application config.

      config :nbpr_linux,
        config_fragments: ["config/linux/wireguard.fragment"],
        patches: ["config/linux/0001-some-fix.patch"]

  Paths are relative to the consuming project's root (`File.cwd!/0`). The
  resolved set folds into the artefact cache key via `digest/1`, which hashes
  file *contents* (not paths) so that editing a fragment invalidates the cache
  but moving the project directory does not.

  A kernel package with neither fragments nor patches rebuilds the system's
  kernel byte-for-byte; that's a no-op in effect, but harmless.
  """

  @type t :: %{fragments: [Path.t()], patches: [Path.t()]}

  @doc """
  Reads `:config_fragments` and `:patches` for `app` from application config
  and returns absolute paths, raising if any referenced file is missing.
  """
  @spec resolve(atom(), Path.t()) :: t()
  def resolve(app, project_root \\ File.cwd!()) when is_atom(app) do
    %{
      fragments:
        expand!(Application.get_env(app, :config_fragments, []), project_root, "fragment"),
      patches: expand!(Application.get_env(app, :patches, []), project_root, "patch")
    }
  end

  @doc """
  The `build_opts` cache-key contribution for a kernel package: a single
  `:kernel_config` digest over the resolved fragments and patches, so distinct
  configs get distinct artefacts and editing a fragment forces a rebuild.

  Shared by `mix nbpr.build` and `mix nbpr.fetch` so both derive the same key.
  """
  @spec build_opts(atom(), Path.t()) :: keyword()
  def build_opts(app, project_root \\ File.cwd!()) when is_atom(app) do
    [kernel_config: digest(resolve(app, project_root))]
  end

  @doc """
  A short hex digest over the contents of every fragment and patch, stable
  under reordering. Suitable as a `build_opts` cache-key contributor.
  """
  @spec digest(t()) :: String.t()
  def digest(%{fragments: fragments, patches: patches}) do
    (fragments ++ patches)
    |> Enum.map(&file_fingerprint/1)
    |> Enum.sort()
    |> Enum.join("\n")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp expand!(paths, project_root, label) when is_list(paths) do
    Enum.map(paths, fn path ->
      abs = Path.expand(path, project_root)

      unless File.regular?(abs) do
        raise ArgumentError,
              "nbpr_linux: #{label} not found: #{path} (resolved to #{abs})"
      end

      abs
    end)
  end

  defp file_fingerprint(path) do
    hash = path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
    "#{Path.basename(path)}:#{hash}"
  end
end
