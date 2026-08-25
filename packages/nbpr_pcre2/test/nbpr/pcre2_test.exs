defmodule NBPR.Pcre2Test do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Pcre2.__nbpr_package__()

    assert pkg.module == NBPR.Pcre2
    assert pkg.name == :pcre2
    assert pkg.version == 1
    assert pkg.br_package == "pcre2"
    assert pkg.description == "Perl-compatible regular expression library"
    assert pkg.homepage == "https://www.pcre.org/"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
