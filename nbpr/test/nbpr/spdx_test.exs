defmodule NBPR.SpdxTest do
  use ExUnit.Case, async: false

  alias NBPR.Spdx

  setup do
    artifacts =
      Path.join(System.tmp_dir!(), "nbpr_spdx_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(artifacts)
    System.put_env("NERVES_ARTIFACTS_DIR", artifacts)

    on_exit(fn ->
      System.delete_env("NERVES_ARTIFACTS_DIR")
      File.rm_rf!(artifacts)
    end)

    {:ok, artifacts: artifacts}
  end

  describe "cache_path/0" do
    test "lands under $NERVES_ARTIFACTS_DIR/nbpr", %{artifacts: artifacts} do
      assert Spdx.cache_path() == Path.join([artifacts, "nbpr", "spdx_licenses.json"])
    end
  end

  describe "license_ids/0 and validate/2" do
    setup %{artifacts: artifacts} do
      cache = Path.join([artifacts, "nbpr", "spdx_licenses.json"])
      File.mkdir_p!(Path.dirname(cache))
      File.write!(cache, fixture_json())
      :ok
    end

    test "license_ids/0 reads IDs from the cached file" do
      ids = Spdx.license_ids()
      assert "MIT" in ids
      assert "GPL-2.0-or-later" in ids
      assert "BSD-3-Clause" in ids
    end

    test "validate/2 returns :ok for known IDs" do
      assert :ok = Spdx.validate("MIT")
      assert :ok = Spdx.validate("BSD-3-Clause")
      assert :ok = Spdx.validate("GPL-2.0-or-later")
    end

    test "validate/2 surfaces ranked suggestions for unknown IDs" do
      assert {:error, suggestions} = Spdx.validate("GPL-2.0+", 3)
      assert length(suggestions) == 3
      assert "GPL-2.0-only" in suggestions or "GPL-2.0-or-later" in suggestions
    end

    test "validate/2 caps suggestions at the requested count" do
      assert {:error, suggestions} = Spdx.validate("totally-not-a-license", 2)
      assert length(suggestions) == 2
    end
  end

  defp fixture_json do
    :json.encode(%{
      "licenseListVersion" => "fixture",
      "licenses" => [
        %{"licenseId" => "MIT"},
        %{"licenseId" => "BSD-2-Clause"},
        %{"licenseId" => "BSD-3-Clause"},
        %{"licenseId" => "GPL-2.0-only"},
        %{"licenseId" => "GPL-2.0-or-later"},
        %{"licenseId" => "Apache-2.0"},
        %{"licenseId" => "ISC"}
      ]
    })
    |> IO.iodata_to_binary()
  end
end
