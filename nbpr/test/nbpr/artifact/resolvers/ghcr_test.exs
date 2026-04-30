defmodule NBPR.Artifact.Resolvers.GHCRTest do
  use ExUnit.Case, async: true

  alias NBPR.Artifact
  alias NBPR.Artifact.Resolvers.GHCR

  @inputs %{
    package_name: "nbpr_jq",
    package_version: "1.7.1",
    system_app: :nerves_system_rpi4,
    system_version: "2.0.1",
    build_opts: []
  }

  describe "plan/2" do
    test "returns a plan tuple for ghcr sites" do
      assert {GHCR, plan} = GHCR.plan({:ghcr, "ghcr.io/jimsynz"}, @inputs)
      assert plan.image == "jimsynz/nbpr_jq"
      assert plan.tag == "1.7.1-nerves_system_rpi4-2.0.1-#{Artifact.cache_key(@inputs)}"
    end

    test "ignores other site types" do
      refute GHCR.plan({:github_releases, "jimsynz/nbpr"}, @inputs)
      refute GHCR.plan({:other, "x"}, @inputs)
    end

    test "ignores ghcr sites that don't start with ghcr.io/" do
      refute GHCR.plan({:ghcr, "registry.example.com/foo"}, @inputs)
    end

    test "rejects an empty owner" do
      refute GHCR.plan({:ghcr, "ghcr.io/"}, @inputs)
    end
  end

  describe "tag_for/1" do
    test "follows the canonical tag scheme" do
      assert GHCR.tag_for(@inputs) ==
               "1.7.1-nerves_system_rpi4-2.0.1-#{Artifact.cache_key(@inputs)}"
    end

    test "changes when build_opts change" do
      flipped = %{@inputs | build_opts: [oniguruma: false]}
      assert GHCR.tag_for(flipped) != GHCR.tag_for(@inputs)
    end
  end
end
