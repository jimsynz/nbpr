defmodule NBPR.VersionTest do
  use ExUnit.Case, async: true

  doctest NBPR.Version

  describe "hex_version/1" do
    test "leaves a version already in Hex's shape alone" do
      for version <- ~w(1.8.2 20.10.26 0.25.0 1.10.5) do
        assert NBPR.Version.hex_version(version) == version
      end
    end

    test "pads what upstream leaves out" do
      assert NBPR.Version.hex_version("2.92") == "2.92.0"
      assert NBPR.Version.hex_version("4.8") == "4.8.0"
      assert NBPR.Version.hex_version("34") == "34.0.0"
    end

    test "drops a fourth component" do
      assert NBPR.Version.hex_version("3.1.4.1") == "3.1.4"
    end

    test "drops a numeric patchlevel suffix" do
      assert NBPR.Version.hex_version("7.1.2-26") == "7.1.2"
      assert NBPR.Version.hex_version("7.1.2-9") == "7.1.2"
    end

    test "strips leading zeros, which semver forbids and Mix rejects" do
      assert NBPR.Version.hex_version("2.03.31") == "2.3.31"
      assert NBPR.Version.hex_version("01.02.03") == "1.2.3"
    end

    test "passes a non-numeric suffix through rather than claim the release" do
      for version <- ~w(1.2.3-rc1 2.0_p1 1.2.3+4 5.0.0-alpha.1) do
        assert NBPR.Version.hex_version(version) == version
      end
    end

    test "output is always publishable for every shape it recognises" do
      for version <- ~w(1.8.2 2.92 34 3.1.4.1 7.1.2-26 2.03.31 3.1.4.1.7) do
        assert NBPR.Version.validate(NBPR.Version.hex_version(version)) == :ok
      end
    end

    test "is idempotent, so re-normalising a normalised version is safe" do
      for version <- ~w(1.8.2 2.92 34 3.1.4.1 7.1.2-26) do
        once = NBPR.Version.hex_version(version)
        assert NBPR.Version.hex_version(once) == once
      end
    end
  end

  describe "validate/1" do
    test "accepts exactly MAJOR.MINOR.PATCH" do
      for version <- ~w(0.0.0 1.8.2 34.0.0 20.10.26) do
        assert NBPR.Version.validate(version) == :ok
      end
    end

    test "rejects build metadata, which hex.pm refuses outright" do
      assert {:error, message} = NBPR.Version.validate("3.1.4+1")
      assert message =~ "build number not allowed"
    end

    test "rejects a pre-release, which no `~>` requirement resolves" do
      assert {:error, message} = NBPR.Version.validate("7.1.2-26")
      assert message =~ "resolver"
    end

    test "rejects anything Version can't parse" do
      for version <- ~w(2.92 34 3.1.4.1 1.02.3) do
        assert {:error, message} = NBPR.Version.validate(version)
        assert message =~ "MAJOR.MINOR.PATCH"
      end
    end
  end

  describe "normalise_version_source/0" do
    setup do
      # The text packages carry has to behave exactly like the function that
      # documents it, so compile it and hold the two to the same table.
      module = :NBPRVersionSourceProbe

      source = """
      defmodule #{inspect(module)} do
        def call(version), do: normalise_version(version)

      #{NBPR.Version.normalise_version_source()}
      end
      """

      Code.with_diagnostics(fn -> Code.eval_string(source) end)

      {:ok, probe: module}
    end

    test "agrees with hex_version/1 on every shape Buildroot produces", %{probe: probe} do
      for version <- ~w(1.8.2 2.92 34 4.8 3.1.4.1 7.1.2-26 2.03.31 20.10.26 1.2.3-rc1) do
        assert apply(probe, :call, [version]) == NBPR.Version.hex_version(version),
               "the carried copy and hex_version/1 disagree on #{inspect(version)}"
      end
    end
  end

  describe "the escapes this module closes off" do
    test "build metadata cannot order a rebuild above the release" do
      assert Version.compare("3.1.4+1", "3.1.4") == :eq
    end

    test "a pre-release sorts below the release it was meant to supersede" do
      assert Version.compare("7.1.2-26", "7.1.2") == :lt
    end
  end
end
