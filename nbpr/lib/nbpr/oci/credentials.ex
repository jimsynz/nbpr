defmodule NBPR.OCI.Credentials do
  @moduledoc false

  # Shared by GHCR pulls and pushes. Read at request time so credentials can
  # come from the CI environment without being embedded in package metadata.
  def ghcr do
    case System.get_env("GHCR_TOKEN") || System.get_env("GITHUB_TOKEN") do
      nil -> nil
      token -> {System.get_env("GHCR_USERNAME") || "oauth", token}
    end
  end

  def ghcr! do
    ghcr() || raise "GHCR_TOKEN or GITHUB_TOKEN env var required to push to ghcr.io"
  end

  def pull_headers do
    case ghcr() do
      nil ->
        []

      {username, token} ->
        [
          {~c"authorization",
           String.to_charlist("Basic " <> Base.encode64("#{username}:#{token}"))}
        ]
    end
  end
end
