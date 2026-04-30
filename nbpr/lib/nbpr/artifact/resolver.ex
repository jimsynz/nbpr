defmodule NBPR.Artifact.Resolver do
  @moduledoc """
  Behaviour for nbpr artefact resolvers.

  Each resolver maps a site spec (e.g. `{:github_releases, "owner/repo"}`) plus
  build inputs to a fetch plan, then performs the actual fetch.

  `plan/2` is a pure function: it returns `{__MODULE__, plan_map}` if the
  resolver handles this kind of site, or `nil` to skip. The fetcher iterates
  resolvers per site and uses the first non-`nil` plan it gets.

  `get/2` performs the actual HTTP download to the destination path. It must
  clean up partial downloads on failure.
  """

  alias NBPR.Artifact
  alias NBPR.Package

  @type plan :: {module(), map()}

  @callback plan(Package.artifact_site(), Artifact.build_inputs()) :: plan() | nil
  @callback get(map(), Path.t()) :: :ok | {:error, term()}
end
