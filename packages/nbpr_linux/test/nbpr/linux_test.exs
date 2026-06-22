defmodule NBPR.LinuxTest do
  use ExUnit.Case, async: true

  test "package metadata is a well-formed kernel package" do
    pkg = NBPR.Linux.__nbpr_package__()

    assert pkg.module == NBPR.Linux
    assert pkg.name == :linux
    assert pkg.version == 1
    assert pkg.kind == :kernel
    assert pkg.br_package == nil
    assert pkg.br_external_path == nil
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
    assert pkg.artifact_sites == [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
  end
end
