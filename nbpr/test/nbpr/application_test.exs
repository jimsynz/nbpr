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

    test "exports every present bin/sbin dir on PATH and lib dir on LD_LIBRARY_PATH" do
      System.put_env("PATH", "/orig/bin")
      System.put_env("LD_LIBRARY_PATH", "/orig/lib")

      {_app, priv} = load_fake_package(~w(bin usr/sbin lib usr/lib))

      NBPR.Application.setup_env!()

      path = String.split(System.get_env("PATH"), ":")
      lib_path = String.split(System.get_env("LD_LIBRARY_PATH"), ":")

      assert Path.join(priv, "bin") in path
      assert Path.join(priv, "usr/sbin") in path
      assert Path.join(priv, "lib") in lib_path
      assert Path.join(priv, "usr/lib") in lib_path

      # Existing entries are preserved (prepended, not clobbered).
      assert "/orig/bin" in path
      assert "/orig/lib" in lib_path
    end

    test "skips subdirs the package doesn't ship" do
      {_app, priv} = load_fake_package(~w(bin lib))

      NBPR.Application.setup_env!()

      path = String.split(System.get_env("PATH") || "", ":")
      refute Path.join(priv, "usr/bin") in path
      refute Path.join(priv, "sbin") in path
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

  # Builds a loadable `nbpr_*` fixture app on the code path with the given priv
  # subdirs present, so `setup_env!/0` discovers it exactly as a real package.
  defp load_fake_package(subdirs) do
    n = System.unique_integer([:positive])
    name = "nbpr_fake#{n}"
    app = String.to_atom(name)
    # `:code.priv_dir/1` resolves the app dir by matching the ebin's parent
    # directory name against the app name, so the app dir must be named exactly.
    app_dir = Path.join([System.tmp_dir!(), "nbpr_fake_fixtures_#{n}", name])
    ebin = Path.join(app_dir, "ebin")
    File.mkdir_p!(ebin)

    spec = {:application, app, [description: ~c"fake", vsn: ~c"0.0.0"]}

    File.write!(
      Path.join(ebin, "#{name}.app"),
      :erlang.iolist_to_binary(:io_lib.format("~p.", [spec]))
    )

    Enum.each(subdirs, &File.mkdir_p!(Path.join([app_dir, "priv", &1])))

    Code.prepend_path(ebin)
    :ok = Application.load(app)

    on_exit(fn ->
      Application.unload(app)
      Code.delete_path(ebin)
      File.rm_rf!(Path.dirname(app_dir))
    end)

    {app, Path.join(app_dir, "priv")}
  end
end
