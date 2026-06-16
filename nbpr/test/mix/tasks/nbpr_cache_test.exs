defmodule Mix.Tasks.Nbpr.CacheTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Nbpr.Cache, as: Task
  alias NBPR.Artifact.Cache

  setup do
    artifacts =
      Path.join(System.tmp_dir!(), "nbpr_cache_test_#{System.unique_integer([:positive])}")

    root = Path.join(artifacts, "nbpr")
    File.mkdir_p!(root)
    System.put_env("NERVES_ARTIFACTS_DIR", artifacts)

    on_exit(fn ->
      System.delete_env("NERVES_ARTIFACTS_DIR")
      File.rm_rf!(artifacts)
    end)

    {:ok, root: root}
  end

  describe "Cache.list/0" do
    test "returns only cache-root subdirs that carry a manifest.json", %{root: root} do
      seed_entry!(
        root,
        "nbpr_jq-1.7.1-nerves_system_rpi4-1.30.0-aaaa",
        manifest("nbpr_jq", "1.7.1")
      )

      File.mkdir_p!(Path.join(root, "dl"))
      File.mkdir_p!(Path.join(root, "no_manifest"))

      assert [entry] = Cache.list()
      assert entry.dir == "nbpr_jq-1.7.1-nerves_system_rpi4-1.30.0-aaaa"
      assert entry.manifest["package_name"] == "nbpr_jq"
    end

    test "returns [] when the cache root is absent" do
      System.put_env(
        "NERVES_ARTIFACTS_DIR",
        Path.join(System.tmp_dir!(), "nbpr_absent_#{System.unique_integer([:positive])}")
      )

      assert Cache.list() == []
    end
  end

  describe "entries_to_remove/2" do
    test "removes everything by default" do
      entries = [entry("a", "nbpr_jq", 2), entry("b", "nbpr_jq", 1)]
      assert Task.entries_to_remove(entries, []) == entries
    end

    test "with --keep-latest keeps the newest entry per package" do
      newest = entry("jq-new", "nbpr_jq", 30)
      older = entry("jq-old", "nbpr_jq", 10)
      other = entry("dnsmasq", "nbpr_dnsmasq", 5)

      removed = Task.entries_to_remove([older, newest, other], keep_latest: true)

      assert removed == [older]
    end
  end

  describe "run/1 list" do
    test "summarises each cached artefact", %{root: root} do
      seed_entry!(
        root,
        "nbpr_jq-1.7.1-nerves_system_rpi4-1.30.0-aaaa",
        manifest("nbpr_jq", "1.7.1")
      )

      output = capture_io(fn -> Task.run(["list"]) end)

      assert output =~ "nbpr_jq-1.7.1-nerves_system_rpi4-1.30.0-aaaa"
      assert output =~ "[nbpr_jq 1.7.1 → nerves_system_rpi4 1.30.0]"
      assert output =~ "1 cached artefact(s)"
    end

    test "reports an empty cache" do
      output = capture_io(fn -> Task.run(["list"]) end)
      assert output =~ "cache is empty"
    end
  end

  describe "run/1 info" do
    test "prints the resolved tuple from the manifest", %{root: root} do
      seed_entry!(
        root,
        "nbpr_jq-1.7.1-nerves_system_rpi4-1.30.0-aaaa",
        manifest("nbpr_jq", "1.7.1")
      )

      output =
        capture_io(fn -> Task.run(["info", "nbpr_jq-1.7.1-nerves_system_rpi4-1.30.0-aaaa"]) end)

      assert output =~ "package:        nbpr_jq 1.7.1"
      assert output =~ "system:         nerves_system_rpi4 1.30.0"
      assert output =~ "oniguruma=true"
    end

    test "raises for an unknown entry" do
      assert_raise Mix.Error, ~r/no cache entry named/, fn ->
        capture_io(fn -> Task.run(["info", "nope"]) end)
      end
    end
  end

  describe "run/1 clean" do
    test "--dry-run lists without deleting", %{root: root} do
      seed_entry!(
        root,
        "nbpr_jq-1.7.1-nerves_system_rpi4-1.30.0-aaaa",
        manifest("nbpr_jq", "1.7.1")
      )

      output = capture_io(fn -> Task.run(["clean", "--dry-run"]) end)

      assert output =~ "would remove 1 entr"
      assert Cache.list() != []
    end

    test "--yes removes all entries", %{root: root} do
      seed_entry!(
        root,
        "nbpr_jq-1.7.1-nerves_system_rpi4-1.30.0-aaaa",
        manifest("nbpr_jq", "1.7.1")
      )

      seed_entry!(
        root,
        "nbpr_dnsmasq-2.91-nerves_system_rpi4-1.30.0-bbbb",
        manifest("nbpr_dnsmasq", "2.91")
      )

      output = capture_io(fn -> Task.run(["clean", "--yes"]) end)

      assert output =~ "removed 2 entr"
      assert Cache.list() == []
    end

    test "reports nothing to remove on an empty cache" do
      output = capture_io(fn -> Task.run(["clean", "--yes"]) end)
      assert output =~ "nothing to remove"
    end
  end

  test "rejects an unknown subcommand" do
    assert_raise Mix.Error, ~r/usage:/, fn -> Task.run(["bogus"]) end
  end

  defp manifest(package_name, version) do
    %{
      "package_name" => package_name,
      "package_version" => version,
      "system_app" => "nerves_system_rpi4",
      "system_version" => "1.30.0",
      "build_opts" => %{"oniguruma" => true},
      "cache_key" => "deadbeef",
      "schema_version" => 1
    }
  end

  defp seed_entry!(root, dir, manifest_map) do
    entry_dir = Path.join(root, dir)
    File.mkdir_p!(entry_dir)

    File.write!(
      Path.join(entry_dir, "manifest.json"),
      IO.iodata_to_binary(:json.encode(manifest_map))
    )
  end

  defp entry(dir, package_name, mtime) do
    %{dir: dir, path: "/tmp/#{dir}", manifest: %{"package_name" => package_name}, mtime: mtime}
  end
end
