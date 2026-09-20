defmodule NBPR.BluezAlsaTest do
  use ExUnit.Case, async: true

  describe "package metadata" do
    test "is well-formed" do
      pkg = NBPR.BluezAlsa.__nbpr_package__()

      assert pkg.module == NBPR.BluezAlsa
      assert pkg.name == :bluez_alsa
      assert pkg.version == 1
      assert pkg.br_package == "bluez-alsa"
      assert pkg.homepage == "https://github.com/Arkq/bluez-alsa"
      assert pkg.artifact_sites == [ghcr: "ghcr.io/jimsynz/nbpr"]
      assert pkg.kernel_modules == []

      # `alsa-lib` reads this in preference to its compiled-in plugin directory,
      # which is where the plugin would be on a Buildroot rootfs and is not where
      # an NBPR package lands.
      assert pkg.runtime_env == [{"ALSA_PLUGIN_DIR", "${NBPR_PRIV}/usr/lib/alsa-lib"}]

      [daemon] = pkg.daemons
      assert daemon.name == :bluealsad
      assert daemon.module == NBPR.BluezAlsa.Bluealsad
      assert daemon.path == "/usr/bin/bluealsad"
    end
  end

  describe "generated daemon module" do
    test "exports child_spec/1, start_link/1, argv/1, binary_path/0" do
      assert Code.ensure_loaded?(NBPR.BluezAlsa.Bluealsad)
      assert function_exported?(NBPR.BluezAlsa.Bluealsad, :child_spec, 1)
      assert function_exported?(NBPR.BluezAlsa.Bluealsad, :start_link, 1)
      assert function_exported?(NBPR.BluezAlsa.Bluealsad, :argv, 1)
      assert function_exported?(NBPR.BluezAlsa.Bluealsad, :binary_path, 0)
    end

    test "binary_path/0 resolves under the package's priv dir" do
      path = NBPR.BluezAlsa.Bluealsad.binary_path()

      assert path =~ "lib/nbpr_bluez_alsa"
      assert String.ends_with?(path, "usr/bin/bluealsad")
    end
  end

  describe "argv/1" do
    test "names the profile that a caller asked for" do
      argv = NBPR.BluezAlsa.Bluealsad.argv(profiles: ["a2dp-source"])

      assert "-p" in argv
      assert "a2dp-source" in argv
    end

    test "names an adapter when it is given one" do
      argv = NBPR.BluezAlsa.Bluealsad.argv(profiles: ["a2dp-sink"], device: "hci0")

      assert "-i" in argv
      assert "hci0" in argv
    end

    # A daemon with no profile routes nothing, so it is required rather than
    # defaulted: a caller that forgot would get silence and no error.
    test "raises when no profile is named" do
      assert_raise NimbleOptions.ValidationError, fn ->
        NBPR.BluezAlsa.Bluealsad.argv([])
      end
    end
  end
end
