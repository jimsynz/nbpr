defmodule NBPR.LibcurlTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Libcurl.__nbpr_package__()

      assert pkg.module == NBPR.Libcurl
      assert pkg.name == :libcurl
      assert pkg.version == 1
      assert pkg.br_package == "libcurl"
      assert pkg.description == "Multi-protocol file transfer library"
      assert pkg.homepage == "https://curl.se/"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end
  end

  describe "build options" do
    test "curl_binary maps to its Buildroot flag and defaults off" do
      pkg = NBPR.Libcurl.__nbpr_package__()

      assert Keyword.keys(pkg.build_opts) == [:curl_binary]
      assert pkg.build_opt_extensions[:curl_binary].br_flag == "BR2_PACKAGE_LIBCURL_CURL"

      validated = NimbleOptions.validate!([], NimbleOptions.new!(pkg.build_opts))
      assert validated[:curl_binary] == false
    end
  end
end
