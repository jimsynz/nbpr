defmodule Mix.Tasks.Nbpr.MatrixTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Nbpr.Matrix

  describe "module_for/1" do
    test "strips the `nbpr_` prefix and camelizes the remainder" do
      assert Matrix.module_for("nbpr_jq") == "NBPR.Jq"
      assert Matrix.module_for("nbpr_dnsmasq") == "NBPR.Dnsmasq"
    end

    test "preserves underscores via standard camelize semantics" do
      assert Matrix.module_for("nbpr_some_thing") == "NBPR.SomeThing"
    end
  end
end
