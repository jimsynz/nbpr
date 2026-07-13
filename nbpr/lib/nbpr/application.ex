defmodule NBPR.Application do
  @moduledoc """
  Sets up `PATH`, `LD_LIBRARY_PATH`, and any package-declared `runtime_env` so
  external programs spawned by the BEAM can find every loaded nbpr package's
  binaries, shared libraries, and runtime resources.

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

  # Binaries can land in any of these (Buildroot installs to bin/sbin AND
  # usr/bin/usr/sbin), and libraries in lib OR usr/lib. These MUST match
  # `NBPR.Artifact.LibCheck`'s notion of "provided" (it counts usr/lib + lib),
  # or the firmware-time check passes for a soname/binary that's then invisible
  # at runtime.
  @bin_subdirs ~w(bin sbin usr/bin usr/sbin)
  @lib_subdirs ~w(lib usr/lib)

  @doc false
  @spec setup_env!() :: :ok
  def setup_env! do
    packages = nbpr_packages()
    priv_dirs = Enum.map(packages, & &1.priv)

    paths = subdirs(priv_dirs, @bin_subdirs)
    lib_paths = subdirs(priv_dirs, @lib_subdirs)

    prepend_env("PATH", paths)
    prepend_env("LD_LIBRARY_PATH", lib_paths)

    Enum.each(runtime_env_assignments(packages), fn {var, value} ->
      prepend_env(var, [value])
    end)

    :ok
  end

  @doc false
  @spec runtime_env_assignments([%{priv: Path.t(), runtime_env: [{String.t(), String.t()}]}]) ::
          [{String.t(), String.t()}]
  def runtime_env_assignments(packages) do
    for %{priv: priv, runtime_env: runtime_env} <- packages,
        {var, template} <- runtime_env,
        do: {var, expand(template, priv)}
  end

  @doc false
  @spec expand(String.t(), Path.t()) :: String.t()
  def expand(template, priv) do
    String.replace(template, "${NBPR_PRIV}", priv)
  end

  defp subdirs(priv_dirs, subdirs) do
    for priv <- priv_dirs, sub <- subdirs, dir = Path.join(priv, sub), File.dir?(dir), do: dir
  end

  defp nbpr_packages do
    for {app, _, _} <- Application.loaded_applications(),
        name = Atom.to_string(app),
        String.starts_with?(name, "nbpr_"),
        app != :nbpr,
        priv = priv_dir(app),
        not is_nil(priv),
        do: %{priv: priv, runtime_env: runtime_env_for(app)}
  end

  defp runtime_env_for(app) do
    module = derive_module(app)

    if Code.ensure_loaded?(module) and function_exported?(module, :__nbpr_package__, 0) do
      module.__nbpr_package__().runtime_env
    else
      []
    end
  end

  defp derive_module(app) do
    short = app |> Atom.to_string() |> String.replace_prefix("nbpr_", "")
    Module.concat(["NBPR", Macro.camelize(short)])
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
