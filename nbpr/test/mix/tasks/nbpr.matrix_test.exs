defmodule NBPR.MatrixFixtureKernel do
  use NBPR.BrPackage, version: 1, kernel: true, description: "matrix kernel fixture"
end

defmodule NBPR.MatrixFixtureUser do
  use NBPR.BrPackage, version: 1, br_package: "jq", description: "matrix userspace fixture"
end

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

  describe "kernel_package?/1" do
    test "is true for a kernel package" do
      assert Matrix.kernel_package?("nbpr_matrix_fixture_kernel")
    end

    test "is false for a userspace package" do
      refute Matrix.kernel_package?("nbpr_matrix_fixture_user")
    end

    test "defaults to false (included) when the module can't be loaded" do
      refute Matrix.kernel_package?("nbpr_does_not_exist")
    end
  end
end
