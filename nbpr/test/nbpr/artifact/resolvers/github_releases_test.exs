defmodule NBPR.Artifact.Resolvers.GitHubReleasesTest do
  use ExUnit.Case, async: true

  alias NBPR.Artifact
  alias NBPR.Artifact.Resolvers.GitHubReleases

  @inputs %{
    package_name: "nbpr_jq",
    package_version: "0.1.0",
    system_app: :nerves_system_rpi4,
    system_version: "1.30.0",
    build_opts: []
  }

  describe "plan/2" do
    test "returns a plan tuple for github_releases sites" do
      assert {GitHubReleases, plan} =
               GitHubReleases.plan({:github_releases, "jimsynz/nbpr"}, @inputs)

      assert plan.owner_repo == "jimsynz/nbpr"
      assert plan.tag == "nbpr_jq-v0.1.0"
      assert is_binary(plan.url)
    end

    test "returns nil for non-github sites" do
      refute GitHubReleases.plan({:other_thing, "foo"}, @inputs)
    end
  end

  describe "build_url/2" do
    test "follows the canonical release-asset URL pattern" do
      url = GitHubReleases.build_url("jimsynz/nbpr", @inputs)

      assert url ==
               "https://github.com/jimsynz/nbpr/releases/download/" <>
                 "nbpr_jq-v0.1.0/" <>
                 Artifact.tarball_name(@inputs)
    end

    test "tag includes only package name and version, not system or key" do
      url = GitHubReleases.build_url("owner/repo", @inputs)
      assert url =~ "/download/nbpr_jq-v0.1.0/"
    end
  end
end
