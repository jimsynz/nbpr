defmodule NBPR.PackTest do
  use ExUnit.Case, async: false

  @inputs %{
    package_name: "nbpr_jq",
    package_version: "1.7.1",
    system_app: :nerves_system_rpi4,
    system_version: "2.0.1",
    build_opts: [oniguruma: true]
  }

  setup do
    tmp = Path.join(System.tmp_dir!(), "nbpr_pack_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "pack!/3" do
    test "produces a tarball with the canonical filename and shape", %{tmp: tmp} do
      target_src = Path.join(tmp, "src/target")
      File.mkdir_p!(Path.join(target_src, "usr/bin"))
      File.write!(Path.join(target_src, "usr/bin/jq"), "#!/bin/sh\necho stub\n")

      legal_src = Path.join(tmp, "src/legal-info")
      File.mkdir_p!(legal_src)
      File.write!(Path.join(legal_src, "jq.txt"), "MIT")

      output_dir = Path.join(tmp, "out")

      tarball =
        NBPR.Pack.pack!(@inputs, %{target: target_src, legal_info: legal_src}, output_dir)

      assert Path.basename(tarball) == NBPR.Artifact.tarball_name(@inputs)
      assert File.regular?(tarball)

      # Inspect contents via :erl_tar.table/2
      {:ok, entries} =
        :erl_tar.table(String.to_charlist(tarball), [:compressed])

      paths = Enum.map(entries, &to_string/1)

      dir = NBPR.Artifact.dir_name(@inputs)
      assert "#{dir}/manifest.json" in paths
      assert "#{dir}/target/usr/bin/jq" in paths
      assert "#{dir}/legal-info/jq.txt" in paths

      # Should NOT contain a staging dir since we didn't supply one
      refute Enum.any?(paths, &String.starts_with?(&1, "#{dir}/staging"))
    end

    test "round-trips through Cache.extract!/2", %{tmp: tmp} do
      target_src = Path.join(tmp, "src/target")
      File.mkdir_p!(Path.join(target_src, "usr/bin"))
      File.write!(Path.join(target_src, "usr/bin/jq"), "stub")

      output_dir = Path.join(tmp, "out")
      tarball = NBPR.Pack.pack!(@inputs, %{target: target_src}, output_dir)

      cache_root = Path.join(tmp, "cache")
      System.put_env("NERVES_ARTIFACTS_DIR", cache_root)

      try do
        :ok = NBPR.Artifact.Cache.extract!(tarball, @inputs)

        cache_dir = NBPR.Artifact.cache_dir(@inputs)
        assert File.regular?(Path.join(cache_dir, "manifest.json"))
        assert File.read!(Path.join(cache_dir, "target/usr/bin/jq")) == "stub"

        manifest = :json.decode(File.read!(Path.join(cache_dir, "manifest.json")))
        assert manifest["package_name"] == "nbpr_jq"
        assert manifest["cache_key"] == NBPR.Artifact.cache_key(@inputs)
      after
        System.delete_env("NERVES_ARTIFACTS_DIR")
      end
    end

    test "rootfs source ends up as the rootfs/ subdir in the tarball", %{tmp: tmp} do
      target_src = Path.join(tmp, "src/target")
      File.mkdir_p!(Path.join(target_src, "usr/sbin"))
      File.write!(Path.join(target_src, "usr/sbin/zpool"), "stub")

      rootfs_src = Path.join(tmp, "src/rootfs")
      File.mkdir_p!(Path.join(rootfs_src, "lib/modules/6.12.0/extra"))
      File.write!(Path.join(rootfs_src, "lib/modules/6.12.0/extra/zfs.ko"), "stub kmod")

      output_dir = Path.join(tmp, "out")
      tarball = NBPR.Pack.pack!(@inputs, %{target: target_src, rootfs: rootfs_src}, output_dir)

      {:ok, entries} = :erl_tar.table(String.to_charlist(tarball), [:compressed])
      paths = Enum.map(entries, &to_string/1)
      dir = NBPR.Artifact.dir_name(@inputs)

      assert "#{dir}/target/usr/sbin/zpool" in paths
      assert "#{dir}/rootfs/lib/modules/6.12.0/extra/zfs.ko" in paths
    end

    test "raises when a source path is not a directory", %{tmp: tmp} do
      bogus = Path.join(tmp, "not-a-dir")
      File.write!(bogus, "i am a file")

      assert_raise RuntimeError, ~r/not a directory/, fn ->
        NBPR.Pack.pack!(@inputs, %{target: bogus}, Path.join(tmp, "out"))
      end
    end

    test "accepts a relative output_dir (CI passes `-o out/`)", %{tmp: tmp} do
      target_src = Path.join(tmp, "src/target")
      File.mkdir_p!(Path.join(target_src, "usr/bin"))
      File.write!(Path.join(target_src, "usr/bin/jq"), "stub")

      original_cwd = File.cwd!()
      File.cd!(tmp)

      try do
        File.mkdir_p!("out")
        tarball = NBPR.Pack.pack!(@inputs, %{target: target_src}, "out")

        assert File.regular?(tarball)
        # Tarball must be absolute (so callers don't have to track cwd)
        # and named correctly.
        assert Path.type(tarball) == :absolute
        assert Path.basename(tarball) == NBPR.Artifact.tarball_name(@inputs)
      after
        File.cd!(original_cwd)
      end
    end
  end
end
