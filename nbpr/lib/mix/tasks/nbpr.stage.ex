defmodule Mix.Tasks.Nbpr.Stage do
  @shortdoc "Overlay nbpr package staging onto the Nerves sysroot for NIF cross-compiles"

  @moduledoc """
  Some nbpr packages provide libraries that a project's own NIFs link at
  *cross-compile* time (e.g. libsrtp for `ex_libsrtp`). `mix nbpr.fetch` ships
  each package's runtime `target/` into `priv/`, but the headers + `.pc` files a
  NIF build needs live in the artefact's `staging/`. This task overlays that
  staging onto the Nerves build sysroot — by pointing `NERVES_SYSTEM` at a
  shadow system whose `staging/` carries the extra libs, so the shared system
  artefact is never mutated.

  ## When this has to run

  The overlay only helps a NIF that links these libraries at *cross-compile*
  time if `NERVES_SYSTEM` already points at the shadow when that NIF's compiler
  runs. An alias is **not** enough to guarantee that: Mix compiles every
  dependency before it will run a dependency-defined task, so by the time a
  `firmware`/`compile` alias could invoke `nbpr.stage` the dependency NIFs have
  already built against the unmodified sysroot. A project `compilers:` entry is
  no earlier — those run after deps compile too.

  For a NIF in your *own* application (compiled after deps, when the project
  itself compiles), a consumer-side function alias runs early enough:

      def project do
        [aliases: [compile: [&stage_nbpr/1, "compile"]], ...]
      end

      defp stage_nbpr(_args), do: Mix.Task.run("nbpr.stage")

  NIFs pulled in as *dependencies* compile before any project alias step, so
  staging them automatically needs a hook in the Nerves bootstrap chain — the
  point where `Nerves.Env.bootstrap/0` sets the cross-compile env, before
  `deps.compile`. That hook is forthcoming; until it lands this task is the
  validated overlay mechanism, run manually or via the function alias above.

  Once `NERVES_SYSTEM` points at the shadow, the Nerves env bootstrap derives
  the cross-compile sysroot (`PKG_CONFIG_SYSROOT_DIR`, `--sysroot`, ...) from it,
  so NIFs that build after the repoint see the staged libraries.
  """

  use Mix.Task

  alias Mix.Tasks.Nbpr.Fetch
  alias NBPR.Sysroot

  @impl Mix.Task
  def run(_args) do
    if Mix.target() == :host do
      Mix.raise("mix nbpr.stage must run with a real MIX_TARGET; got :host")
    end

    # Load dep paths + the Nerves env WITHOUT compiling the app's deps — the
    # whole point is to redirect the sysroot before ex_libsrtp & friends build.
    Mix.Task.run("loadpaths", ["--no-compile", "--no-deps-check"])
    load_nbpr_apps()

    system_app = Fetch.system_app!()
    system_version = Fetch.system_version!(system_app)
    packages = Fetch.discover_packages()

    staging_dirs =
      for {app, module} <- packages,
          {_pkg, cache_dir} = Fetch.ensure_cached!(app, module, system_app, system_version),
          staging = Path.join(cache_dir, "staging"),
          File.dir?(staging),
          do: staging

    case staging_dirs do
      [] ->
        Mix.shell().info("[nbpr.stage] no package staging to overlay; nothing to do.")

      dirs ->
        real_system = apply(Nerves.Env, :system_path, [])
        real_staging = Path.join(real_system, "staging")
        shadow = Path.join([Mix.Project.build_path(), "nerves", "nbpr_sysroot_shadow"])

        shadow_staging = Sysroot.system_shadow!(real_system, dirs, shadow)

        # Point NERVES_SYSTEM at the shadow so a later env bootstrap derives the
        # sysroot from it; also repoint directly in case the env was already
        # bootstrapped against the real staging.
        System.put_env("NERVES_SYSTEM", shadow)
        Sysroot.repoint_env!(real_staging, shadow_staging)

        Mix.shell().info(
          "[nbpr.stage] overlaid #{length(dirs)} package staging dir(s); " <>
            "NERVES_SYSTEM -> #{shadow}"
        )
    end
  end

  # The nbpr metadata modules must be loadable for discovery. `loadpaths` put
  # their (already-compiled) ebins on disk; make sure they're on the code path
  # and loaded.
  defp load_nbpr_apps do
    for ebin <- Path.wildcard(Path.join([Mix.Project.build_path(), "lib", "*", "ebin"])) do
      Code.prepend_path(ebin)
    end

    for {app, _path} <- Mix.Project.deps_paths(),
        app == :nbpr or String.starts_with?(Atom.to_string(app), "nbpr_") do
      Application.load(app)
    end
  end
end
