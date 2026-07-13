defmodule NBPR.Buildroot.Backend.Shell do
  @moduledoc """
  Buildroot backend that runs `make` natively on the host.

  Only usable inside the Nerves canonical build env (`mix nerves.system.shell`
  or the `nerves_system_br` container), detected by `in_canonical_env?/0`.
  There the toolchain wrappers, sysroot paths, and ABI flags already match the
  canonical build, so no container is needed — and nesting one would be
  redundant.

  Unlike the container backends, extraction happens on the host in Elixir
  (`NBPR.Buildroot.FilesList.copy!/4`) because the build dir is a plain
  directory the host can read directly.
  """

  @behaviour NBPR.Buildroot.Backend

  alias NBPR.Buildroot.{Build, FilesList}

  @impl true
  def available?, do: in_canonical_env?()

  @impl true
  def build!(spec) do
    ensure_linux!()

    output_dir = spec.output_dir
    File.mkdir_p!(output_dir)
    File.write!(Path.join(output_dir, ".config"), spec.defconfig_text)

    run_make!(spec.br_source, output_dir, spec.env, ["olddefconfig"])

    # `<pkg>-dirclean && <pkg>` (not `<pkg>-rebuild`) so BR snapshots the
    # before/after target trees and writes a populated `.files-list*.txt`.
    # See NBPR.Buildroot.FilesList for the rationale.
    run_make!(spec.br_source, output_dir, spec.env, ["#{spec.br_package}-dirclean"])
    run_make!(spec.br_source, output_dir, spec.env, [spec.br_package])

    # Best-effort: packages without `FOO_LICENSE_FILES` declared get no output.
    _ =
      try do
        run_make!(spec.br_source, output_dir, spec.env, ["#{spec.br_package}-legal-info"])
      rescue
        _ -> :ok
      end

    extract_dir = output_dir <> ".extract"
    File.rm_rf!(extract_dir)
    build_dir = locate_build_dir!(output_dir, spec.br_package)
    pp_src = Path.join([output_dir, "per-package", spec.br_package])
    pp_dst = Path.join([extract_dir, "per-package", spec.br_package])

    FilesList.copy!(
      Path.join(pp_src, "target"),
      Path.join(pp_dst, "target"),
      Path.join(build_dir, ".files-list.txt")
    )

    FilesList.copy!(
      staging_src(pp_src),
      Path.join(pp_dst, "staging"),
      Path.join(build_dir, ".files-list-staging.txt"),
      keep_dev: true
    )

    collect_legal_info!(output_dir, spec.br_package, pp_dst)

    extract_dir
  end

  @doc """
  Returns `true` when we're already running inside a Nerves canonical build env
  (so a container backend would be redundant).

  Detection: `IN_NERVES_DEV_SHELL=1` env var, or `/home/nerves/project` exists
  on disk (the standard working dir in nerves_system_br images).
  """
  @spec in_canonical_env?() :: boolean()
  def in_canonical_env? do
    System.get_env("IN_NERVES_DEV_SHELL") == "1" or File.dir?("/home/nerves/project")
  end

  defp collect_legal_info!(output_dir, br_package, pp_dst) do
    pattern = Path.join([output_dir, "legal-info", "licenses", "#{br_package}-*"])

    with [licenses_dir | _] <- Path.wildcard(pattern) |> Enum.filter(&File.dir?/1),
         license_files = list_files(licenses_dir),
         [_ | _] <- license_files do
      legal_info_dir = Path.join(pp_dst, "legal-info")
      File.mkdir_p!(legal_info_dir)
      out_path = Path.join(legal_info_dir, "#{br_package}.txt")
      contents = license_files |> Enum.map(&File.read!/1) |> Enum.join("\n\n\n")
      File.write!(out_path, contents)
    else
      _ -> :ok
    end
  end

  defp list_files(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
  end

  defp locate_build_dir!(output_dir, br_package) do
    pattern = Path.join([output_dir, "build", "#{br_package}-*"])

    case Path.wildcard(pattern) |> Enum.filter(&File.dir?/1) do
      [dir] ->
        dir

      [] ->
        raise "could not locate build dir for #{br_package} under #{Path.dirname(pattern)}"

      many ->
        raise "multiple build dirs match #{pattern}: #{inspect(many)}"
    end
  end

  # Locates the per-package STAGING_DIR. With a Nerves (external) toolchain,
  # `STAGING_DIR` is the toolchain sysroot at `<pp>/host/<tuple>/sysroot`, not a
  # separate `<pp>/staging` dir — that's where `.files-list-staging.txt` paths
  # are rooted. Falls back to `<pp>/staging` for an internal toolchain.
  defp staging_src(pp_src) do
    case Path.wildcard(Path.join(pp_src, "host/*/sysroot")) do
      [dir | _] -> dir
      [] -> Path.join(pp_src, "staging")
    end
  end

  defp ensure_linux! do
    case :os.type() do
      {:unix, :linux} ->
        :ok

      other ->
        raise """
        Buildroot build currently requires a Linux host; detected #{inspect(other)}.

        On other hosts the build runs in a container instead (docker/podman).
        For a native build, run `mix nbpr.build` on a Linux machine or inside
        `mix nerves.system.shell` (which gives you a Linux shell with BR already
        set up).
        """
    end
  end

  defp run_make!(cwd, output_dir, env, targets) do
    args = Build.make_args(output_dir, targets)
    cmd = "make #{Enum.join(args, " ")}"
    Mix.shell().info("[nbpr] running: #{cmd}")

    case System.cmd("make", args,
           cd: cwd,
           env: env,
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {_, status} ->
        raise "Buildroot `#{cmd}` failed with exit status #{status}"
    end
  end
end
