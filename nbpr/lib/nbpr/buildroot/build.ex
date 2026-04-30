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

  Currently Linux-only. macOS and other hosts will be supported via a
  Docker wrapper in a later phase.
  """

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
  @spec build!(Path.t(), Path.t(), String.t(), String.t(), [{String.t(), String.t()}]) ::
          Path.t()
  def build!(br_source, output_dir, defconfig_text, br_package, extra_env \\ [])
      when is_binary(br_source) and is_binary(output_dir) and is_binary(defconfig_text) and
             is_binary(br_package) and is_list(extra_env) do
    ensure_linux!()

    File.mkdir_p!(output_dir)
    File.write!(Path.join(output_dir, ".config"), defconfig_text)

    env = build_env() ++ extra_env

    run_make!(br_source, output_dir, env, ["olddefconfig"])
    run_make!(br_source, output_dir, env, ["#{br_package}-rebuild"])

    output_dir
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
