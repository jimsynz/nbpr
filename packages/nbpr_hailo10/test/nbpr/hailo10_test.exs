defmodule NBPR.Hailo10Test do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Hailo10.__nbpr_package__()

    assert pkg.module == NBPR.Hailo10
    assert pkg.name == :hailo10
    assert pkg.br_external_path == "buildroot"

    assert pkg.br_packages == [
             "spdlog_hailort",
             "hailort",
             "hailort-firmware",
             "hailort-drivers"
           ]

    assert pkg.kernel_modules == ["hailo1x_pci"]
    assert pkg.expose_staging == true
    assert pkg.targets == [:rpi5]
  end

  test "generates an Application that declares the hailo1x_pci module" do
    assert NBPR.Hailo10.Application.kernel_modules() == ["hailo1x_pci"]
  end

  test "the vendored Buildroot external tree is present" do
    root = Path.join([__DIR__, "..", "..", "buildroot"]) |> Path.expand()

    assert File.regular?(Path.join(root, "external.desc"))

    for sub <- ~w(spdlog_hailort hailort hailort-firmware hailort-drivers) do
      assert File.dir?(Path.join([root, "package", sub])),
             "missing package/#{sub} in vendored tree"
    end
  end
end
