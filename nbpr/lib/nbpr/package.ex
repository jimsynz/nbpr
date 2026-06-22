defmodule NBPR.Package do
  @moduledoc """
  Metadata struct describing an NBPR package.

  Returned by the generated `__nbpr_package__/0` callback on every module that
  does `use NBPR.BrPackage`. The struct is the canonical introspection surface
  for the curated CI, the build runner, and any future tooling.
  """

  alias NBPR.Package.Daemon

  @type artifact_site :: {:github_releases, String.t()} | {:ghcr, String.t()}

  @type kind :: :userspace | :kernel

  @type t :: %__MODULE__{
          name: atom(),
          version: pos_integer(),
          kind: kind(),
          module: module(),
          description: String.t(),
          homepage: String.t() | nil,
          br_package: String.t() | nil,
          br_external_path: String.t() | nil,
          build_opts: keyword(),
          build_opt_extensions: %{atom() => map()},
          daemons: [Daemon.t()],
          kernel_modules: [String.t()],
          artifact_sites: [artifact_site()]
        }

  defstruct name: nil,
            version: nil,
            kind: :userspace,
            module: nil,
            description: nil,
            homepage: nil,
            br_package: nil,
            br_external_path: nil,
            build_opts: [],
            build_opt_extensions: %{},
            daemons: [],
            kernel_modules: [],
            artifact_sites: []
end
