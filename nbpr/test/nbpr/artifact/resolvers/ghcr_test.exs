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

    test "preserves multi-segment owner paths so packages attach to a repo" do
      assert {GHCR, plan} = GHCR.plan({:ghcr, "ghcr.io/jimsynz/nbpr"}, @inputs)
      assert plan.image == "jimsynz/nbpr/nbpr_jq"
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

    test "substitutes the `+` a build-metadata version carries into the tag" do
      inputs = %{@inputs | package_version: "3.1.4+1"}

      assert GHCR.tag_for(inputs) ==
               "3.1.4_1-nerves_system_rpi4-2.0.1-#{Artifact.cache_key(inputs)}"
    end

    test "keys off the unsanitised version, so `3.1.4+1` and `3.1.4_1` differ" do
      plus = %{@inputs | package_version: "3.1.4+1"}
      underscore = %{@inputs | package_version: "3.1.4_1"}

      assert GHCR.tag_for(plus) != GHCR.tag_for(underscore)
    end
  end

  describe "sanitise_tag/1" do
    test "leaves a tag already in the OCI alphabet untouched" do
      tag = "1.7.1-nerves_system_rpi4-2.0.1-cb13a42462c2806d"
      assert GHCR.sanitise_tag(tag) == tag
    end

    test "replaces every byte outside the OCI alphabet with `_`" do
      assert GHCR.sanitise_tag("1.0.0+a/b:c~d") == "1.0.0_a_b_c_d"
    end

    test "output matches the tag grammar from the distribution spec" do
      assert GHCR.sanitise_tag("3.1.4+1-nerves_system_bbb-2.30.1-9bef615fb1839352") =~
               ~r/^[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}$/
    end
  end
end
