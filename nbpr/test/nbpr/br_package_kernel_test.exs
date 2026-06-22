defmodule NBPR.BrPackageKernelTest do
  use ExUnit.Case, async: true

  describe "kernel: true" do
    defmodule KernelPkg do
      use NBPR.BrPackage,
        version: 1,
        kernel: true,
        description: "test kernel package",
        artifact_sites: [{:ghcr, "ghcr.io/example/nbpr"}]
    end

    test "produces a :kernel package with no BR source" do
      pkg = KernelPkg.__nbpr_package__()

      assert pkg.kind == :kernel
      assert pkg.br_package == nil
      assert pkg.br_external_path == nil
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end
  end

  describe "kernel: true validation" do
    test "rejects combining with :br_package" do
      assert_raise ArgumentError, ~r/mutually exclusive.*:br_package/, fn ->
        defmodule BadBrPackage do
          use NBPR.BrPackage,
            version: 1,
            kernel: true,
            br_package: "jq",
            description: "bad"
        end
      end
    end

    test "rejects combining with :daemons" do
      assert_raise ArgumentError, ~r/mutually exclusive.*:daemons/, fn ->
        defmodule BadDaemons do
          use NBPR.BrPackage,
            version: 1,
            kernel: true,
            description: "bad",
            daemons: [d: [path: "/usr/sbin/d"]]
        end
      end
    end
  end

  describe "userspace packages still require a BR source" do
    test "rejects neither br_package nor br_external_path" do
      assert_raise ArgumentError, ~r/exactly one of :br_package/, fn ->
        defmodule NoSource do
          use NBPR.BrPackage, version: 1, description: "bad"
        end
      end
    end
  end
end
