defmodule NBPR.BuildrootTest do
  use ExUnit.Case, async: true

  alias NBPR.Buildroot

  setup do
    tmp = Path.join(System.tmp_dir!(), "nbpr_br_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "br_version/1" do
    test "extracts NERVES_BR_VERSION from create-build.sh", %{tmp: tmp} do
      File.write!(Path.join(tmp, "create-build.sh"), """
      #!/usr/bin/env bash
      set -e

      NERVES_BR_VERSION=2025.11.3
      NERVES_BR_DL_DIR=$HOME/.nerves/dl
      """)

      assert Buildroot.br_version(tmp) == {:ok, "2025.11.3"}
    end

    test "returns error when create-build.sh has no version line", %{tmp: tmp} do
      File.write!(Path.join(tmp, "create-build.sh"), "#!/bin/bash\necho hi\n")
      assert Buildroot.br_version(tmp) == {:error, :br_version_not_found_in_create_build_sh}
    end

    test "returns error when create-build.sh is missing", %{tmp: tmp} do
      assert {:error, :enoent} = Buildroot.br_version(tmp)
    end
  end

  describe "patches_path/1 and patch_files/1" do
    test "returns the patches/buildroot dir when present", %{tmp: tmp} do
      patches = Path.join([tmp, "patches", "buildroot"])
      File.mkdir_p!(patches)
      assert Buildroot.patches_path(tmp) == {:ok, patches}
    end

    test "returns :not_found when missing", %{tmp: tmp} do
      assert Buildroot.patches_path(tmp) == {:error, :not_found}
    end

    test "patch_files lists .patch entries in sorted order", %{tmp: tmp} do
      patches = Path.join([tmp, "patches", "buildroot"])
      File.mkdir_p!(patches)

      File.write!(Path.join(patches, "0003-third.patch"), "")
      File.write!(Path.join(patches, "0001-first.patch"), "")
      File.write!(Path.join(patches, "0002-second.patch"), "")
      File.write!(Path.join(patches, "README.md"), "ignored")

      assert Buildroot.patch_files(patches) == [
               "0001-first.patch",
               "0002-second.patch",
               "0003-third.patch"
             ]
    end
  end
end
