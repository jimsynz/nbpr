defmodule NBPR.Hailo10Test do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Hailo10.__nbpr_package__()

    assert pkg.module == NBPR.Hailo10
    assert pkg.name == :hailo10
    assert pkg.version == 1
    assert pkg.br_package == nil
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
    assert pkg.artifact_sites == [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
  end

  test "generates an Application that declares the hailo1x_pci module" do
    assert NBPR.Hailo10.Application.kernel_modules() == ["hailo1x_pci"]
  end

  test "the vendored Buildroot external tree is present and well-formed" do
    root = Path.join([__DIR__, "..", "..", "buildroot"]) |> Path.expand()

    assert File.regular?(Path.join(root, "external.desc"))
    assert File.regular?(Path.join(root, "external.mk"))
    assert File.regular?(Path.join(root, "Config.in"))

    for sub <- ~w(spdlog_hailort hailort hailort-firmware hailort-drivers) do
      assert File.dir?(Path.join([root, "package", sub])),
             "missing package/#{sub} in vendored tree"
    end

    assert File.regular?(Path.join([root, "package", "hailort", "0001-Patch-for-Nerves.patch"]))
  end
end
