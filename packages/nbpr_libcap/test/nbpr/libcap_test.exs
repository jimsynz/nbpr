defmodule NBPR.LibcapTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Libcap.__nbpr_package__()

      assert pkg.module == NBPR.Libcap
      assert pkg.name == :libcap
      assert pkg.version == 1
      assert pkg.br_package == "libcap"
      assert pkg.homepage == "https://sites.google.com/site/fullycapable/"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end
  end

  describe "build options" do
    test "tools maps to its Buildroot flag and defaults off" do
      pkg = NBPR.Libcap.__nbpr_package__()

      assert Keyword.keys(pkg.build_opts) == [:tools]
      assert pkg.build_opt_extensions[:tools].br_flag == "BR2_PACKAGE_LIBCAP_TOOLS"

      validated = NimbleOptions.validate!([], NimbleOptions.new!(pkg.build_opts))
      assert validated[:tools] == false
    end
  end
end
