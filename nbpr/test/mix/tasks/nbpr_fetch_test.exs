defmodule Mix.Tasks.Nbpr.FetchTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Nbpr.Fetch

  describe "derive_module/1" do
    test "maps an app name to the NBPR.<Camel> module" do
      assert Fetch.derive_module(:nbpr_jq) == NBPR.Jq
      assert Fetch.derive_module("nbpr_jq") == NBPR.Jq
      assert Fetch.derive_module(:nbpr_dnsmasq) == NBPR.Dnsmasq
      assert Fetch.derive_module(:nbpr_some_long_name) == NBPR.SomeLongName
    end
  end

  describe "apply_overlays/1" do
    setup do
      Application.put_env(:nerves, :firmware, [])

      on_exit(fn ->
        Application.delete_env(:nerves, :firmware)
      end)

      :ok
    end

    test "appends to extra_rootfs_overlays without overwriting other firmware config" do
      Application.put_env(:nerves, :firmware,
        rootfs_overlay: ["/user/overlay"],
        extra_rootfs_overlays: ["/preexisting"]
      )

      Fetch.apply_overlays(["/nbpr/jq/target", "/nbpr/dnsmasq/target"])

      cfg = Application.get_env(:nerves, :firmware)
      assert Keyword.fetch!(cfg, :rootfs_overlay) == ["/user/overlay"]

      assert Keyword.fetch!(cfg, :extra_rootfs_overlays) == [
               "/preexisting",
               "/nbpr/jq/target",
               "/nbpr/dnsmasq/target"
             ]
    end

    test "creates :extra_rootfs_overlays when missing" do
      Application.put_env(:nerves, :firmware, [])

      Fetch.apply_overlays(["/nbpr/jq/target"])

      assert Keyword.fetch!(Application.get_env(:nerves, :firmware), :extra_rootfs_overlays) ==
               ["/nbpr/jq/target"]
    end
  end
end
