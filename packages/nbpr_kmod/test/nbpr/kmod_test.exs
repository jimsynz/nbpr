defmodule NBPR.KmodTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Kmod.__nbpr_package__()

    assert pkg.module == NBPR.Kmod
    assert pkg.name == :kmod
    assert pkg.version == 1
    assert pkg.br_package == "kmod"
    assert pkg.homepage == "https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git"
    assert pkg.artifact_sites == [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end

  test "tools build opt defaults on and maps to BR2_PACKAGE_KMOD_TOOLS" do
    pkg = NBPR.Kmod.__nbpr_package__()

    assert %{br_flag: "BR2_PACKAGE_KMOD_TOOLS"} = pkg.build_opt_extensions[:tools]
    assert Keyword.fetch!(pkg.build_opts, :tools)[:default] == true
  end
end
