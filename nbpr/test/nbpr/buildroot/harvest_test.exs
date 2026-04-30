defmodule NBPR.Buildroot.HarvestTest do
  use ExUnit.Case, async: true

  alias NBPR.Buildroot.Harvest

  setup do
    tmp = Path.join(System.tmp_dir!(), "nbpr_harvest_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "harvest!/2" do
    test "returns target and staging paths when present", %{tmp: tmp} do
      pp = Path.join([tmp, "per-package", "jq"])
      File.mkdir_p!(Path.join([pp, "target", "usr", "bin"]))
      File.mkdir_p!(Path.join([pp, "staging", "usr", "include"]))
      File.write!(Path.join([pp, "target", "usr", "bin", "jq"]), "stub")

      sources = Harvest.harvest!(tmp, "jq")

      assert sources[:target] == Path.join(pp, "target")
      assert sources[:staging] == Path.join(pp, "staging")
    end

    test "returns only target when staging is absent", %{tmp: tmp} do
      pp = Path.join([tmp, "per-package", "jq"])
      File.mkdir_p!(Path.join([pp, "target", "usr", "bin"]))

      sources = Harvest.harvest!(tmp, "jq")

      assert Map.has_key?(sources, :target)
      refute Map.has_key?(sources, :staging)
    end

    test "raises when per-package output dir is missing", %{tmp: tmp} do
      assert_raise RuntimeError, ~r/no per-package output found/, fn ->
        Harvest.harvest!(tmp, "jq")
      end
    end

    test "raises when per-package dir exists but has neither target nor staging", %{tmp: tmp} do
      pp = Path.join([tmp, "per-package", "jq"])
      File.mkdir_p!(pp)

      assert_raise RuntimeError, ~r/contains neither target.*nor staging/, fn ->
        Harvest.harvest!(tmp, "jq")
      end
    end
  end
end
