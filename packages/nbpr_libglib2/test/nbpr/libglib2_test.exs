defmodule NBPR.Libglib2Test do
  use ExUnit.Case, async: true

  test "package metadata is well-formed" do
    pkg = NBPR.Libglib2.__nbpr_package__()

    assert pkg.module == NBPR.Libglib2
    assert pkg.name == :libglib2
    assert pkg.version == 1
    assert pkg.br_package == "libglib2"
    assert pkg.description == "Low-level core utility library behind GTK and GNOME"
    assert pkg.homepage == "https://gitlab.gnome.org/GNOME/glib"
    assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
    assert pkg.daemons == []
    assert pkg.kernel_modules == []
  end
end
