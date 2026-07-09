defmodule NBPR.Package do
  @moduledoc """
  Metadata struct describing an NBPR package.

  Returned by the generated `__nbpr_package__/0` callback on every module that
  does `use NBPR.BrPackage`. The struct is the canonical introspection surface
  for the curated CI, the build runner, and any future tooling.
  """

  alias NBPR.Package.Daemon

  @type artifact_site :: {:github_releases, String.t()} | {:ghcr, String.t()}

  @type t :: %__MODULE__{
          name: atom(),
          version: pos_integer(),
          module: module(),
          description: String.t(),
          homepage: String.t() | nil,
          br_package: String.t() | nil,
          br_external_path: String.t() | nil,
          br_packages: [String.t()],
          expose_staging: boolean(),
          rootfs_paths: [String.t()],
          build_opts: keyword(),
          build_opt_extensions: %{atom() => map()},
          daemons: [Daemon.t()],
          kernel_modules: [String.t()],
          runtime_env: [{String.t(), String.t()}],
          artifact_sites: [artifact_site()],
          targets: [atom()]
        }

  defstruct [
    :name,
    :version,
    :module,
    :description,
    :homepage,
    :br_package,
    :br_external_path,
    :build_opts,
    :build_opt_extensions,
    :daemons,
    :kernel_modules,
    :runtime_env,
    :artifact_sites,
    br_packages: [],
    expose_staging: false,
    rootfs_paths: ["lib/firmware"],
    targets: []
  ]

  @doc """
  Returns the list of Buildroot package names this nbpr package builds and
  harvests.

  For a mainline package this is the single `:br_package`. For a vendored
  package (an external tree under `:br_external_path`) it's the explicit
  `:br_packages` list, in dependency order — the order Buildroot targets are
  invoked and their per-package outputs merged.
  """
  @spec br_targets(t()) :: [String.t()]
  def br_targets(%__MODULE__{br_package: br_package}) when is_binary(br_package),
    do: [br_package]

  def br_targets(%__MODULE__{br_packages: br_packages}) when is_list(br_packages),
    do: br_packages
end
