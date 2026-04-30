defmodule NBPR.Buildroot.Build do
  @moduledoc """
  Drives a per-package Buildroot build.

  Given a patched BR source tree (from `NBPR.Buildroot.Source.ensure!/2`),
  a stable output dir, a rendered defconfig (from
  `NBPR.Buildroot.Defconfig.render!/3`), and a Buildroot package name,
  runs `make olddefconfig` followed by `make <pkg>-rebuild` to produce
  per-package output at `<output_dir>/per-package/<pkg>/{target,staging}`.

  ## Output dir reuse

  The caller supplies the `output_dir`. For interactive speed, use a
  stable per-(system, BR-version) path — the toolchain extraction,
  host-skeleton, host-fakedate, and other shared steps then survive
  between invocations and only the package being rebuilt actually
  compiles. `make olddefconfig` reconciles defconfig drift across
  builds (e.g. enabling a different `BR2_PACKAGE_*=y`).

  When invoked outside the Nerves canonical build env (`mix nerves.system.shell`),
  delegates `make` invocations to `NBPR.Buildroot.Docker`, which runs them
  inside `ghcr.io/nerves-project/nerves_system_br:latest`. Detection is
  via `NBPR.Buildroot.Docker.in_canonical_env?/0` — the native path is
  taken inside the canonical container and the Docker path everywhere else.
  """

  alias NBPR.Buildroot.Docker
  alias NBPR.Buildroot.FilesList
  alias NBPR.Buildroot.Source

  @doc """
  Builds `br_package` against `defconfig_text` using the BR tree at
  `br_source`, with output going to `output_dir`. Returns `output_dir`.

  `extra_env` is merged into the make invocation's env. Use it to pass
  Nerves-specific variables that the system's defconfig references —
  most importantly `NERVES_DEFCONFIG_DIR` (so `BR2_GLOBAL_PATCH_DIR`
  resolves) and `BR2_EXTERNAL` (so the system's BR external tree is
  visible).

  `output_dir` is created if missing. Existing contents are preserved —
  this is the design — so subsequent builds reuse the toolchain,
  skeleton, and other unchanging packages. To force from-scratch,
  `File.rm_rf!(output_dir)` before calling.
  """
  @spec build!(Path.t(), Path.t(), String.t(), String.t(), [{String.t(), String.t()}], keyword()) ::
          Path.t()
  def build!(br_source, output_dir, defconfig_text, br_package, extra_env \\ [], opts \\ [])
      when is_binary(br_source) and is_binary(output_dir) and is_binary(defconfig_text) and
             is_binary(br_package) and is_list(extra_env) do
    env = build_env() ++ extra_env
    extra_mounts = Keyword.get(opts, :extra_mounts, [])

    if Docker.in_canonical_env?() do
      ensure_linux!()
      File.mkdir_p!(output_dir)
      File.write!(Path.join(output_dir, ".config"), defconfig_text)
      run_make!(br_source, output_dir, env, ["olddefconfig"])

      # `<pkg>-dirclean && <pkg>` (not `<pkg>-rebuild`) so BR snapshots the
      # before/after target trees and writes a populated `.files-list*.txt`.
      # See NBPR.Buildroot.FilesList for the rationale.
      run_make!(br_source, output_dir, env, ["#{br_package}-dirclean"])
      run_make!(br_source, output_dir, env, [br_package])

      extract_dir = output_dir <> ".extract"
      File.rm_rf!(extract_dir)
      build_dir = locate_build_dir!(output_dir, br_package)
      pp_src = Path.join([output_dir, "per-package", br_package])
      pp_dst = Path.join([extract_dir, "per-package", br_package])

      FilesList.copy!(
        Path.join(pp_src, "target"),
        Path.join(pp_dst, "target"),
        Path.join(build_dir, ".files-list.txt")
      )

      FilesList.copy!(
        Path.join(pp_src, "staging"),
        Path.join(pp_dst, "staging"),
        Path.join(build_dir, ".files-list-staging.txt")
      )

      extract_dir
    else
      # Docker path: run BR build in a named volume (so hardlinks work),
      # extract per-package output to a host-accessible bind-mount dir.
      #
      # `extract_dir` MUST be a sibling of `output_dir`, never nested inside.
      # `output_dir` is mounted as a Docker named volume; bind-mounting another
      # path at a subpath of that volume creates filesystem-layering ambiguity
      # (e.g. `rm -rf` inside the container only affects the overlay, not the
      # underlying volume contents at the same path), which manifests as
      # `cp: ... File exists` errors during extraction.
      slug = Path.basename(output_dir)
      volume = Docker.volume_name(slug)
      extract_dir = output_dir <> ".extract"

      Docker.build!(
        br_source: br_source,
        build_path: output_dir,
        volume: volume,
        extract_dir: extract_dir,
        defconfig_text: defconfig_text,
        br_package: br_package,
        env: env,
        extra_mounts: extra_mounts
      )

      # Return the dir Harvest will read — it has `per-package/<br_package>/`
      # populated from the volume.
      extract_dir
    end
  end

  @doc false
  @spec make_args(Path.t(), [String.t()]) :: [String.t()]
  def make_args(output_dir, targets) when is_binary(output_dir) and is_list(targets) do
    ["O=#{output_dir}" | targets]
  end

  @doc false
  @spec build_env() :: [{String.t(), String.t()}]
  def build_env do
    [{"BR2_DL_DIR", Source.download_dir()}]
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

  defp ensure_linux! do
    case :os.type() do
      {:unix, :linux} ->
        :ok

      other ->
        raise """
        Buildroot build currently requires a Linux host; detected #{inspect(other)}.

        macOS and other hosts will be supported via a Docker wrapper in a
        later phase. For now, run `mix nbpr.build` on a Linux machine or
        inside `mix nerves.system.shell` (which gives you a Linux shell
        with BR already set up).
        """
    end
  end

  defp run_make!(cwd, output_dir, env, targets) do
    args = make_args(output_dir, targets)
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
