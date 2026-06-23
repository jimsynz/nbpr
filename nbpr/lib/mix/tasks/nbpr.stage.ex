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

  It must run *before* the app's deps compile. Wire it at the front of the
  build, and crucially give it no compile-triggering requirement of its own:

      aliases: ["firmware": ["nbpr.stage", "nbpr.fetch", "firmware"]]

  When the firmware build then bootstraps the Nerves env, it derives the
  cross-compile sysroot (`PKG_CONFIG_SYSROOT_DIR`, `--sysroot`, ...) from the
  shadow — so the project's NIFs see the staged libraries.
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
