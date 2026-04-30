defmodule NBPR.JqTest do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Jq.__nbpr_package__()

    assert pkg.module == NBPR.Jq
    assert pkg.name == :jq
    assert pkg.version == 1
    assert pkg.br_package == "jq"
    assert pkg.description == "Lightweight JSON processor"
    assert pkg.homepage == "https://jqlang.github.io/jq/"
    assert pkg.artifact_sites == [{:ghcr, "ghcr.io/jimsynz"}]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
