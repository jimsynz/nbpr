defmodule NBPR.Application do
  @moduledoc """
  Sets up `PATH` and `LD_LIBRARY_PATH` so external programs spawned by the BEAM
  can find every loaded nbpr package's binaries and shared libraries.

  Each nbpr package ships its `target/` artefacts under its own `priv/` (so
  Mix release semantics stay intact and packages can't stomp on each other in
  the rootfs). At runtime, `:code.priv_dir/1` points at the right place, but
  child processes invoked via `System.cmd/2`, `Port.open/2`, or MuonTrap need
  `PATH` and `LD_LIBRARY_PATH` populated to find sibling-package binaries and
  inter-package shared libraries (e.g. `nbpr_ffmpeg` linking against
  `libavcodec.so` from `nbpr_libav`).

  This Application sets both env vars *once* at boot, before any user code
  starts. `:nbpr` is a transitive dependency of every nbpr package, so OTP's
  application start order guarantees this runs first. By the time
  `Application.loaded_applications/0` is queried, every nbpr_* `.app` file
  is loaded into the application controller (load is separate from start),
  so `:code.priv_dir/1` resolves correctly for all of them.
  """

  use Application

  @impl Application
  def start(_type, _args) do
    setup_env!()
    Supervisor.start_link([], strategy: :one_for_one, name: __MODULE__)
  end

  @doc false
  @spec setup_env!() :: :ok
  def setup_env! do
    nbpr_packages = nbpr_priv_dirs()

    bin_paths = Enum.map(nbpr_packages, &Path.join(&1, "usr/bin"))
    sbin_paths = Enum.map(nbpr_packages, &Path.join(&1, "usr/sbin"))
    paths = bin_paths |> Enum.concat(sbin_paths) |> Enum.filter(&File.dir?/1)

    lib_paths =
      nbpr_packages
      |> Enum.map(&Path.join(&1, "usr/lib"))
      |> Enum.filter(&File.dir?/1)

    prepend_env("PATH", paths)
    prepend_env("LD_LIBRARY_PATH", lib_paths)
    :ok
  end

  defp nbpr_priv_dirs do
    for {app, _, _} <- Application.loaded_applications(),
        name = Atom.to_string(app),
        String.starts_with?(name, "nbpr_"),
        app != :nbpr,
        priv = priv_dir(app),
        not is_nil(priv),
        do: priv
  end

  defp priv_dir(app) do
    case :code.priv_dir(app) do
      {:error, _} -> nil
      path -> to_string(path)
    end
  end

  defp prepend_env(_var, []), do: :ok

  defp prepend_env(var, paths) do
    new = Enum.join(paths, ":")

    case System.get_env(var) do
      nil -> System.put_env(var, new)
      "" -> System.put_env(var, new)
      existing -> System.put_env(var, new <> ":" <> existing)
    end
  end
end
