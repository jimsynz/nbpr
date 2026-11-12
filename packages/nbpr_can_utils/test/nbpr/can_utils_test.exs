defmodule NBPR.CanUtilsTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.CanUtils.__nbpr_package__()

      assert pkg.module == NBPR.CanUtils
      assert pkg.name == :can_utils
      assert pkg.version == 1
      assert pkg.description == "Userspace tools for Linux SocketCAN"
      assert pkg.homepage == "https://github.com/linux-can/can-utils"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.build_opts == []
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end

    test "br_package keeps Buildroot's hyphenated name, unlike the Hex name" do
      assert NBPR.CanUtils.__nbpr_package__().br_package == "can-utils"
    end
  end
end
