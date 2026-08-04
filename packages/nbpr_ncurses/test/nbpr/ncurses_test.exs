defmodule NBPR.NcursesTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Ncurses.__nbpr_package__()

      assert pkg.module == NBPR.Ncurses
      assert pkg.name == :ncurses
      assert pkg.version == 1
      assert pkg.br_package == "ncurses"
      assert pkg.homepage == "https://invisible-island.net/ncurses/"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.daemons == []
      assert pkg.kernel_modules == []
    end
  end

  describe "build options" do
    test "each maps to a Buildroot flag" do
      pkg = NBPR.Ncurses.__nbpr_package__()

      assert Keyword.keys(pkg.build_opts) == [:wchar, :target_progs, :additional_terminfo]

      assert Map.new(pkg.build_opt_extensions, fn {name, ext} -> {name, ext.br_flag} end) == %{
               wchar: "BR2_PACKAGE_NCURSES_WCHAR",
               target_progs: "BR2_PACKAGE_NCURSES_TARGET_PROGS",
               additional_terminfo: "BR2_PACKAGE_NCURSES_ADDITIONAL_TERMINFO"
             }
    end

    # wchar off keeps the sonames as plain `libncurses.so.6`, which is what a
    # consumer built with only BR2_PACKAGE_NCURSES set links against.
    test "defaults match Buildroot's, so consumer sonames line up" do
      pkg = NBPR.Ncurses.__nbpr_package__()
      validated = NimbleOptions.validate!([], NimbleOptions.new!(pkg.build_opts))

      assert validated[:wchar] == false
      assert validated[:target_progs] == false
      assert validated[:additional_terminfo] == ""
    end
  end
end
