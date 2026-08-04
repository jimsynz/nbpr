defmodule NBPR.PpsToolsTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.PpsTools.__nbpr_package__()

      assert pkg.module == NBPR.PpsTools
      assert pkg.name == :pps_tools
      assert pkg.version == 1
      assert pkg.homepage == "https://github.com/redlab-i/pps-tools/"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.build_opts == []
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end

    test "br_package keeps Buildroot's hyphenated name, unlike the Hex name" do
      assert NBPR.PpsTools.__nbpr_package__().br_package == "pps-tools"
    end
  end
end
