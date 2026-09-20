defmodule NBPR.SbcTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Sbc.__nbpr_package__()

      assert pkg.module == NBPR.Sbc
      assert pkg.name == :sbc
      assert pkg.version == 1
      assert pkg.br_package == "sbc"
      assert pkg.homepage == "http://www.bluez.org/"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.kernel_modules == []

      # A library, and nothing to run.
      assert pkg.daemons == []
    end

    test "tools map to the Buildroot flag, and stay off" do
      pkg = NBPR.Sbc.__nbpr_package__()

      assert Keyword.keys(pkg.build_opts) == [:tools]
      assert pkg.build_opts[:tools][:default] == false
      assert pkg.build_opt_extensions[:tools].br_flag == "BR2_PACKAGE_SBC_TOOLS"
    end
  end
end
