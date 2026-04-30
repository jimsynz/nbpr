defmodule NBPR.Artifact.CacheTest do
  use ExUnit.Case, async: false

  @inputs %{
    package_name: "nbpr_jq",
    package_version: "0.1.0",
    system_app: :nerves_system_rpi4,
    system_version: "1.30.0",
    build_opts: []
  }

  setup do
    artifacts_dir =
      Path.join(System.tmp_dir!(), "nbpr_cache_test_#{System.unique_integer([:positive])}")

    System.put_env("NERVES_ARTIFACTS_DIR", artifacts_dir)

    on_exit(fn ->
      System.delete_env("NERVES_ARTIFACTS_DIR")
      File.rm_rf!(artifacts_dir)
    end)

    {:ok, artifacts_dir: artifacts_dir}
  end

  describe "valid?/1" do
    test "returns false when the cache dir does not exist" do
      refute NBPR.Artifact.Cache.valid?(@inputs)
    end

    test "returns true when the cache dir exists" do
      cache_dir = NBPR.Artifact.cache_dir(@inputs)
      File.mkdir_p!(cache_dir)
      assert NBPR.Artifact.Cache.valid?(@inputs)
    end
  end

  describe "extract!/2" do
    test "extracts a valid tarball with a single top-level directory" do
      tarball =
        build_tarball!(NBPR.Artifact.dir_name(@inputs), %{
          "manifest.json" => ~s({"cache_key": "stub"}),
          "target/usr/bin/jq" => "binary stub",
          "legal-info/jq.txt" => "MIT"
        })

      assert NBPR.Artifact.Cache.extract!(tarball, @inputs) == :ok

      cache_dir = NBPR.Artifact.cache_dir(@inputs)
      assert File.regular?(Path.join(cache_dir, "manifest.json"))
      assert File.regular?(Path.join(cache_dir, "target/usr/bin/jq"))
      assert File.regular?(Path.join(cache_dir, "legal-info/jq.txt"))
    end

    test "overwrites an existing cache dir" do
      cache_dir = NBPR.Artifact.cache_dir(@inputs)
      File.mkdir_p!(cache_dir)
      File.write!(Path.join(cache_dir, "stale.txt"), "old")

      tarball =
        build_tarball!(NBPR.Artifact.dir_name(@inputs), %{"manifest.json" => "{}"})

      assert NBPR.Artifact.Cache.extract!(tarball, @inputs) == :ok
      refute File.exists?(Path.join(cache_dir, "stale.txt"))
      assert File.regular?(Path.join(cache_dir, "manifest.json"))
    end

    test "raises when the tarball has multiple top-level entries" do
      tmp = make_tmp_dir!()
      File.mkdir_p!(Path.join(tmp, "first"))
      File.mkdir_p!(Path.join(tmp, "second"))
      tarball = Path.join(tmp, "bad.tar.gz")
      tar_create!(tarball, ["first", "second"], tmp)

      assert_raise RuntimeError, ~r/single top-level directory/, fn ->
        NBPR.Artifact.Cache.extract!(tarball, @inputs)
      end
    end

    test "raises when the tarball top-level entry is a file, not a directory" do
      tmp = make_tmp_dir!()
      File.write!(Path.join(tmp, "loose.txt"), "not a dir")
      tarball = Path.join(tmp, "bad.tar.gz")
      tar_create!(tarball, ["loose.txt"], tmp)

      assert_raise RuntimeError, ~r/found a file/, fn ->
        NBPR.Artifact.Cache.extract!(tarball, @inputs)
      end
    end

    test "raises clearly when the tarball cannot be opened" do
      assert_raise RuntimeError, ~r/failed to extract/, fn ->
        NBPR.Artifact.Cache.extract!("/nonexistent/path.tar.gz", @inputs)
      end
    end
  end

  defp build_tarball!(top_level_name, files) do
    tmp = make_tmp_dir!()
    inner = Path.join(tmp, top_level_name)

    Enum.each(files, fn {relative, content} ->
      full = Path.join(inner, relative)
      full |> Path.dirname() |> File.mkdir_p!()
      File.write!(full, content)
    end)

    tarball = Path.join(tmp, "fixture.tar.gz")
    tar_create!(tarball, [top_level_name], tmp)
    tarball
  end

  defp tar_create!(tarball_path, entries, cwd) do
    File.cd!(cwd, fn ->
      :ok =
        :erl_tar.create(
          String.to_charlist(tarball_path),
          Enum.map(entries, &String.to_charlist/1),
          [:compressed]
        )
    end)
  end

  defp make_tmp_dir! do
    dir = Path.join(System.tmp_dir!(), "nbpr_fixture_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end
end
