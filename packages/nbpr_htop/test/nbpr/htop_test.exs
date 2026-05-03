defmodule NBPR.HtopTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Htop.__nbpr_package__()

    assert pkg.module == NBPR.Htop
    assert pkg.name == :htop
    assert pkg.version == 1
    assert pkg.br_package == "htop"
    assert pkg.description == "Htop is an interactive text-mode process viewer for Linux."
    assert pkg.homepage == "https://htop.dev/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
