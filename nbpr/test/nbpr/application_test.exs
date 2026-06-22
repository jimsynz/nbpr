defmodule NBPR.ApplicationTest do
  use ExUnit.Case, async: false

  describe "setup_env!/0" do
    setup do
      original_path = System.get_env("PATH")
      original_lib_path = System.get_env("LD_LIBRARY_PATH")

      on_exit(fn ->
        if original_path,
          do: System.put_env("PATH", original_path),
          else: System.delete_env("PATH")

        if original_lib_path,
          do: System.put_env("LD_LIBRARY_PATH", original_lib_path),
          else: System.delete_env("LD_LIBRARY_PATH")
      end)

      :ok
    end

    test "is a no-op when no nbpr_* apps are loaded" do
      original = System.get_env("PATH")
      NBPR.Application.setup_env!()
      assert System.get_env("PATH") == original
    end
  end

  describe "expand/2" do
    test "substitutes ${NBPR_PRIV} with the package priv dir" do
      assert NBPR.Application.expand(
               "${NBPR_PRIV}/usr/lib/xtables",
               "/srv/erlang/lib/nbpr_x/priv"
             ) ==
               "/srv/erlang/lib/nbpr_x/priv/usr/lib/xtables"
    end

    test "leaves templates without placeholders untouched" do
      assert NBPR.Application.expand("/abs/path", "/priv") == "/abs/path"
    end
  end

  describe "runtime_env_assignments/1" do
    test "expands each package's runtime_env against its own priv dir" do
      packages = [
        %{priv: "/p/a/priv", runtime_env: [{"XTABLES_LIBDIR", "${NBPR_PRIV}/usr/lib/xtables"}]},
        %{priv: "/p/b/priv", runtime_env: []}
      ]

      assert NBPR.Application.runtime_env_assignments(packages) ==
               [{"XTABLES_LIBDIR", "/p/a/priv/usr/lib/xtables"}]
    end
  end
end
