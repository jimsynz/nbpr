defmodule Mix.Tasks.Nbpr.FetchTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Nbpr.Fetch

  describe "derive_module/1" do
    test "maps an app name to the NBPR.<Camel> module" do
      assert Fetch.derive_module(:nbpr_jq) == NBPR.Jq
      assert Fetch.derive_module("nbpr_jq") == NBPR.Jq
      assert Fetch.derive_module(:nbpr_dnsmasq) == NBPR.Dnsmasq
      assert Fetch.derive_module(:nbpr_some_long_name) == NBPR.SomeLongName
    end
  end

  describe "priv_dir_for/1" do
    test "returns the build-path priv directory for the given app" do
      expected = Path.join([Mix.Project.build_path(), "lib", "nbpr_jq", "priv"])
      assert Fetch.priv_dir_for(:nbpr_jq) == expected
    end
  end
end
