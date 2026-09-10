defmodule NBPR.OCI.CredentialsTest do
  use ExUnit.Case, async: false
  alias NBPR.OCI.Credentials

  setup do
    for key <- ["GHCR_TOKEN", "GITHUB_TOKEN", "GHCR_USERNAME"] do
      original = System.get_env(key)
      System.delete_env(key)

      on_exit(fn ->
        if original, do: System.put_env(key, original), else: System.delete_env(key)
      end)
    end

    :ok
  end

  test "pulls anonymously without credentials; pushes require credentials" do
    assert Credentials.pull_headers() == []
    assert_raise RuntimeError, ~r/GHCR_TOKEN or GITHUB_TOKEN/, &Credentials.ghcr!/0
  end

  test "private pulls use the same explicit credentials as pushes" do
    System.put_env("GHCR_USERNAME", "builder")
    System.put_env("GHCR_TOKEN", "test-token")
    System.put_env("GITHUB_TOKEN", "fallback")
    assert Credentials.ghcr!() == {"builder", "test-token"}

    assert Credentials.pull_headers() == [
             {~c"authorization",
              String.to_charlist("Basic " <> Base.encode64("builder:test-token"))}
           ]
  end

  test "falls back to GITHUB_TOKEN and the default username" do
    System.put_env("GITHUB_TOKEN", "test-token")
    assert Credentials.ghcr!() == {"oauth", "test-token"}
  end
end
