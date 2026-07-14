defmodule NBPR.Buildroot.BackendTest do
  use ExUnit.Case, async: false

  alias NBPR.Buildroot.Backend

  describe "select/0 with NBPR_BUILD_BACKEND" do
    setup do
      on_exit(fn -> System.delete_env("NBPR_BUILD_BACKEND") end)
    end

    test "forces the named backend, bypassing auto-detect" do
      System.put_env("NBPR_BUILD_BACKEND", "shell")
      assert Backend.select() == Backend.Shell

      System.put_env("NBPR_BUILD_BACKEND", "docker")
      assert Backend.select() == Backend.Docker

      System.put_env("NBPR_BUILD_BACKEND", "podman")
      assert Backend.select() == Backend.Podman
    end

    test "raises listing valid names on an unknown backend" do
      System.put_env("NBPR_BUILD_BACKEND", "nope")

      assert_raise RuntimeError, ~r/Unknown NBPR_BUILD_BACKEND.*shell, docker, podman/s, fn ->
        Backend.select()
      end
    end
  end
end
