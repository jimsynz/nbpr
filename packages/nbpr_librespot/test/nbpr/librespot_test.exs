defmodule NBPR.LibrespotTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.Librespot.__nbpr_package__()

      assert pkg.module == NBPR.Librespot
      assert pkg.name == :librespot
      assert pkg.version == 1
      assert pkg.homepage == "https://github.com/librespot-org/librespot"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.kernel_modules == []

      [daemon] = pkg.daemons
      assert daemon.name == :librespot
      assert daemon.module == NBPR.Librespot.Librespot
      assert daemon.path == "/usr/bin/librespot"
    end

    # librespot is not in Buildroot mainline, so this package brings its own tree
    # rather than naming one.
    test "it is vendored, and the tree is beside it" do
      pkg = NBPR.Librespot.__nbpr_package__()

      assert pkg.br_package == nil
      assert pkg.br_external_path == "buildroot"
      assert NBPR.Package.vendored?(pkg)

      # A vendored package takes its Buildroot name from its own.
      assert NBPR.Package.br_name(pkg) == "librespot"
    end

    test "the tree it names holds a Buildroot external" do
      tree = NBPR.Package.external_tree(NBPR.Librespot.__nbpr_package__())

      assert File.exists?(Path.join(tree, "external.desc"))
      assert File.exists?(Path.join(tree, "external.mk"))
      assert File.exists?(Path.join(tree, "Config.in"))
      assert File.exists?(Path.join(tree, "package/librespot/librespot.mk"))
      assert File.exists?(Path.join(tree, "package/librespot/Config.in"))
    end

    # The default feature set builds every backend, and each one needs a library
    # that a Nerves system does not carry.
    test "the build takes the ALSA backend and no other" do
      tree = NBPR.Package.external_tree(NBPR.Librespot.__nbpr_package__())
      mk = File.read!(Path.join(tree, "package/librespot/librespot.mk"))

      assert mk =~ "--no-default-features --features alsa-backend"
      assert mk =~ "$(eval $(cargo-package))"
    end
  end

  describe "generated daemon module" do
    test "exports child_spec/1, start_link/1, argv/1, binary_path/0" do
      assert Code.ensure_loaded?(NBPR.Librespot.Librespot)
      assert function_exported?(NBPR.Librespot.Librespot, :child_spec, 1)
      assert function_exported?(NBPR.Librespot.Librespot, :start_link, 1)
      assert function_exported?(NBPR.Librespot.Librespot, :argv, 1)
      assert function_exported?(NBPR.Librespot.Librespot, :binary_path, 0)
    end

    test "binary_path/0 resolves under the package's priv dir" do
      path = NBPR.Librespot.Librespot.binary_path()

      assert path =~ "lib/nbpr_librespot"
      assert String.ends_with?(path, "usr/bin/librespot")
    end
  end

  describe "argv/1" do
    # librespot never detaches, so there is no foreground flag to get wrong.
    test "the defaults name the backend and the kind of device" do
      argv = NBPR.Librespot.Librespot.argv(name: "Kitchen")

      assert ["--name", "Kitchen"] == Enum.take(argv, 2)
      assert "alsa" in argv
      assert "speaker" in argv
    end

    test "it names the sound card and the cache when it is given them" do
      argv =
        NBPR.Librespot.Librespot.argv(
          name: "Kitchen",
          device: "hw:0,0",
          cache: "/root/spotify",
          disable_audio_cache: true
        )

      assert "hw:0,0" in argv
      assert "/root/spotify" in argv
      assert "--disable-audio-cache" in argv
    end

    # A household with two of these cannot tell one `Librespot` from the other.
    test "raises when no name is given" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NBPR.Librespot.Librespot.argv([])
      end
    end
  end
end
