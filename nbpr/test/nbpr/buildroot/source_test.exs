defmodule NBPR.Buildroot.SourceTest do
  use ExUnit.Case, async: false

  alias NBPR.Buildroot.Source

  @version "2025.11.3-fixture"

  setup do
    artifacts =
      Path.join(System.tmp_dir!(), "nbpr_br_source_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(artifacts)
    System.put_env("NERVES_ARTIFACTS_DIR", artifacts)

    on_exit(fn ->
      System.delete_env("NERVES_ARTIFACTS_DIR")
      File.rm_rf!(artifacts)
    end)

    {:ok, artifacts: artifacts}
  end

  describe "cache_dir/1 and download_dir/0" do
    test "land under $NERVES_ARTIFACTS_DIR/nbpr", %{artifacts: artifacts} do
      assert Source.cache_dir(@version) == Path.join([artifacts, "nbpr", "buildroot", @version])
      assert Source.download_dir() == Path.join([artifacts, "nbpr", "buildroot-dl"])
    end
  end

  describe "cached?/1 and ensure!/2" do
    test "cached? is false before ensure!" do
      refute Source.cached?(@version)
    end

    test "ensure! extracts a fixture tarball and marks it ready", %{artifacts: artifacts} do
      tarball = make_fixture_tarball!(artifacts)
      File.mkdir_p!(Source.download_dir())
      File.cp!(tarball, Path.join(Source.download_dir(), "buildroot-#{@version}.tar.gz"))

      cache = Source.ensure!(@version, nil)

      assert cache == Source.cache_dir(@version)
      assert File.regular?(Path.join(cache, "Makefile"))
      assert File.regular?(Path.join(cache, ".nbpr-ready"))
      assert Source.cached?(@version)
    end

    test "ensure! is a no-op when already cached" do
      cache = Source.cache_dir(@version)
      File.mkdir_p!(cache)
      File.write!(Path.join(cache, ".nbpr-ready"), "")

      assert Source.ensure!(@version, nil) == cache
    end

    test "raises when the tarball doesn't contain the expected dir", %{artifacts: artifacts} do
      tarball = make_misnamed_tarball!(artifacts)
      File.mkdir_p!(Source.download_dir())
      File.cp!(tarball, Path.join(Source.download_dir(), "buildroot-#{@version}.tar.gz"))

      assert_raise RuntimeError, ~r/buildroot-#{@version}/, fn ->
        Source.ensure!(@version, nil)
      end
    end
  end

  describe "apply_patches!/2" do
    test "applies patches in lexicographic order" do
      tmp = make_tmp_dir!()
      tree = Path.join(tmp, "tree")
      File.mkdir_p!(tree)
      File.write!(Path.join(tree, "hello.txt"), "hello world\n")

      patches = Path.join(tmp, "patches")
      File.mkdir_p!(patches)

      File.write!(Path.join(patches, "0001-greet.patch"), """
      --- a/hello.txt
      +++ b/hello.txt
      @@ -1 +1 @@
      -hello world
      +hello universe
      """)

      assert :ok = Source.apply_patches!(tree, patches)

      assert File.read!(Path.join(tree, "hello.txt")) == "hello universe\n"
    end

    test "is a no-op when patches_dir is nil" do
      tmp = make_tmp_dir!()
      assert :ok = Source.apply_patches!(tmp, nil)
    end

    test "raises with the failing patch's output" do
      tmp = make_tmp_dir!()
      tree = Path.join(tmp, "tree")
      File.mkdir_p!(tree)
      File.write!(Path.join(tree, "hello.txt"), "different content\n")

      patches = Path.join(tmp, "patches")
      File.mkdir_p!(patches)

      File.write!(Path.join(patches, "0001-bad.patch"), """
      --- a/hello.txt
      +++ b/hello.txt
      @@ -1 +1 @@
      -hello world
      +hello universe
      """)

      assert_raise RuntimeError, ~r/0001-bad.patch failed/, fn ->
        Source.apply_patches!(tree, patches)
      end
    end
  end

  defp make_fixture_tarball!(_artifacts) do
    tmp = make_tmp_dir!()
    inner = Path.join(tmp, "buildroot-#{@version}")
    File.mkdir_p!(Path.join(inner, "package"))
    File.write!(Path.join(inner, "Makefile"), "# fixture BR Makefile\n")
    File.write!(Path.join([inner, "package", "Makefile.in"]), "# package include\n")

    tarball = Path.join(tmp, "buildroot-#{@version}.tar.gz")
    tar_create!(tarball, ["buildroot-#{@version}"], tmp)
    tarball
  end

  defp make_misnamed_tarball!(_artifacts) do
    tmp = make_tmp_dir!()
    inner = Path.join(tmp, "wrong-dir-name")
    File.mkdir_p!(inner)
    File.write!(Path.join(inner, "Makefile"), "")

    tarball = Path.join(tmp, "buildroot-#{@version}.tar.gz")
    tar_create!(tarball, ["wrong-dir-name"], tmp)
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
    dir = Path.join(System.tmp_dir!(), "nbpr_src_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end
end
