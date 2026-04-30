defmodule NBPR.ArtifactTest do
  use ExUnit.Case, async: true

  @inputs %{
    package_name: "nbpr_jq",
    package_version: "0.1.0",
    system_app: :nerves_system_rpi4,
    system_version: "1.30.0",
    build_opts: [oniguruma: true]
  }

  describe "cache_key/1" do
    test "is deterministic for identical inputs" do
      assert NBPR.Artifact.cache_key(@inputs) == NBPR.Artifact.cache_key(@inputs)
    end

    test "is invariant to build_opts ordering" do
      one = %{@inputs | build_opts: [oniguruma: true, fizz: false]}
      other = %{@inputs | build_opts: [fizz: false, oniguruma: true]}
      assert NBPR.Artifact.cache_key(one) == NBPR.Artifact.cache_key(other)
    end

    test "differs when package_version changes" do
      bumped = %{@inputs | package_version: "0.2.0"}
      assert NBPR.Artifact.cache_key(@inputs) != NBPR.Artifact.cache_key(bumped)
    end

    test "differs when system changes" do
      x86 = %{@inputs | system_app: :nerves_system_x86_64}
      assert NBPR.Artifact.cache_key(@inputs) != NBPR.Artifact.cache_key(x86)
    end

    test "differs when system_version changes" do
      bumped = %{@inputs | system_version: "1.30.1"}
      assert NBPR.Artifact.cache_key(@inputs) != NBPR.Artifact.cache_key(bumped)
    end

    test "differs when build_opts values change" do
      flipped = %{@inputs | build_opts: [oniguruma: false]}
      assert NBPR.Artifact.cache_key(@inputs) != NBPR.Artifact.cache_key(flipped)
    end

    test "is 16 hex characters long" do
      key = NBPR.Artifact.cache_key(@inputs)
      assert String.length(key) == 16
      assert key =~ ~r/^[0-9a-f]+$/
    end
  end

  describe "tarball_name/1 and dir_name/1" do
    test "tarball_name follows the canonical pattern" do
      key = NBPR.Artifact.cache_key(@inputs)

      assert NBPR.Artifact.tarball_name(@inputs) ==
               "nbpr_jq-0.1.0-nerves_system_rpi4-1.30.0-#{key}.tar.gz"
    end

    test "dir_name is the tarball name without the .tar.gz" do
      key = NBPR.Artifact.cache_key(@inputs)
      assert NBPR.Artifact.dir_name(@inputs) == "nbpr_jq-0.1.0-nerves_system_rpi4-1.30.0-#{key}"
    end
  end

  describe "cache_dir/1 and download_path/1" do
    test "respects NERVES_ARTIFACTS_DIR" do
      System.put_env("NERVES_ARTIFACTS_DIR", "/tmp/nbpr_test_artifacts")

      assert NBPR.Artifact.cache_dir(@inputs) =~ ~r{^/tmp/nbpr_test_artifacts/nbpr/}
      assert NBPR.Artifact.download_path(@inputs) =~ ~r{^/tmp/nbpr_test_artifacts/nbpr/dl/}
    after
      System.delete_env("NERVES_ARTIFACTS_DIR")
    end

    test "falls back to XDG_DATA_HOME when NERVES_ARTIFACTS_DIR is unset" do
      System.delete_env("NERVES_ARTIFACTS_DIR")
      System.put_env("XDG_DATA_HOME", "/tmp/nbpr_test_xdg")

      assert NBPR.Artifact.cache_dir(@inputs) =~ ~r{^/tmp/nbpr_test_xdg/nerves/nbpr/}
    after
      System.delete_env("XDG_DATA_HOME")
    end
  end

  describe "manifest/1" do
    test "is a map suitable for JSON encoding" do
      m = NBPR.Artifact.manifest(@inputs)

      assert m["package_name"] == "nbpr_jq"
      assert m["package_version"] == "0.1.0"
      assert m["system_app"] == "nerves_system_rpi4"
      assert m["system_version"] == "1.30.0"
      assert m["build_opts"] == %{"oniguruma" => true}
      assert m["cache_key"] == NBPR.Artifact.cache_key(@inputs)
      assert m["schema_version"] == 1
    end

    test "build_opts atoms are stringified for JSON" do
      m = NBPR.Artifact.manifest(@inputs)
      assert is_map(m["build_opts"])
      assert Map.keys(m["build_opts"]) == ["oniguruma"]
    end
  end
end
