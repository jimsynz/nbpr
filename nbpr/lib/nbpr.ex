defmodule NBPR do
  @moduledoc """
  Nerves Binary Package Repository — the library underpinning every `:nbpr_*` Hex package.

  Provides the `NBPR.BrPackage` macro plus Mix tasks for authoring and inspecting packages.
  See the workspace `CLAUDE.md` for design context.

  ## Running package binaries

  Daemon-bearing packages generate a supervised `child_spec/1`. For one-shot CLI
  invocations, `run/4` is the equivalent ergonomic: it resolves a binary inside a
  package's `priv/` and runs it with an `LD_LIBRARY_PATH` assembled across every
  loaded `:nbpr_*` package, so binaries linked against shared libraries from
  sibling packages (e.g. `mke2fs` from `:nbpr_e2fsprogs` needing `libblkid` from
  `:nbpr_util_linux`) resolve them at runtime:

      NBPR.run(NBPR.E2fsprogs, "sbin/mke2fs", ["-V"])
      #=> {"mke2fs 1.47.3 (8-Jul-2025)\\n", 0}

  `cmd_env/1` hands back just the environment for callers who want to build the
  `System.cmd/3` invocation themselves.
  """

  @doc """
  Runs a binary shipped by an NBPR package as a one-shot command.

  `relative_path` is resolved against the package's `priv/` directory. The
  command runs with the environment from `cmd_env/1` so shared libraries from
  sibling `:nbpr_*` packages resolve at runtime. Returns `System.cmd/3`'s
  `{output, exit_status}`.

  `opts` are passed through to `System.cmd/3`. Any `:env` entries are appended
  after the NBPR-derived environment, so a caller can override or extend it.

      NBPR.run(NBPR.E2fsprogs, "sbin/mke2fs", ["-V"])
      #=> {"mke2fs 1.47.3 (8-Jul-2025)\\n", 0}
  """
  @spec run(module(), Path.t(), [binary()], keyword()) ::
          {Collectable.t(), exit_status :: non_neg_integer()}
  def run(module, relative_path, args \\ [], opts \\ []) when is_atom(module) do
    binary = Path.join(priv_dir!(module), relative_path)
    {extra_env, opts} = Keyword.pop(opts, :env, [])
    System.cmd(binary, args, Keyword.put(opts, :env, cmd_env(module) ++ extra_env))
  end

  @doc """
  Returns the environment needed to run a package's binaries against shared
  libraries shipped by sibling `:nbpr_*` packages.

  Today this is a single `LD_LIBRARY_PATH` entry covering the `usr/lib` and
  `lib` directories of *every* loaded `:nbpr_*` package — `module` is validated
  as a loaded NBPR package but its declared dependencies aren't yet known to the
  metadata, so the path is assembled by groveling all of them. Once packages
  declare cross-package deps this can narrow to just `module`'s closure.

  Returns `[]` when no `:nbpr_*` library directories are present (e.g. a
  self-contained package on a host with nothing else fetched).
  """
  @spec cmd_env(module()) :: [{String.t(), String.t()}]
  def cmd_env(module) when is_atom(module) do
    _ = priv_dir!(module)
    lib_dirs_env(loaded_nbpr_priv_dirs())
  end

  @doc false
  @spec lib_dirs_env([Path.t()]) :: [{String.t(), String.t()}]
  def lib_dirs_env(priv_dirs) do
    dirs =
      for priv <- priv_dirs,
          sub <- ["usr/lib", "lib"],
          dir = Path.join(priv, sub),
          File.dir?(dir),
          do: dir

    case dirs do
      [] -> []
      dirs -> [{"LD_LIBRARY_PATH", Enum.join(dirs, ":")}]
    end
  end

  defp loaded_nbpr_priv_dirs do
    for {app, _, _} <- Application.loaded_applications(),
        app != :nbpr,
        String.starts_with?(Atom.to_string(app), "nbpr_"),
        priv = :code.priv_dir(app),
        is_list(priv),
        do: to_string(priv)
  end

  defp priv_dir!(module) do
    unless Code.ensure_loaded?(module) and function_exported?(module, :__nbpr_package__, 0) do
      raise ArgumentError, "#{inspect(module)} is not an NBPR package (no `__nbpr_package__/0`)"
    end

    app = String.to_atom("nbpr_#{module.__nbpr_package__().name}")

    case :code.priv_dir(app) do
      {:error, _} ->
        raise "priv dir not found for #{inspect(app)}; " <>
                "is the package loaded as an OTP application?"

      path ->
        to_string(path)
    end
  end
end
