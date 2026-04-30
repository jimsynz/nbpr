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
end
