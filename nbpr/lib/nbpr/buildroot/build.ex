defmodule NBPR.Buildroot.Build do
  @moduledoc """
  Drives a per-package Buildroot build.

  Given a patched BR source tree (from `NBPR.Buildroot.Source.ensure!/2`),
  a rendered defconfig (from `NBPR.Buildroot.Defconfig.render!/3`), and a
  Buildroot package name, runs `make olddefconfig` followed by
  `make <pkg>-rebuild` to produce per-package output at
  `<output_dir>/per-package/<pkg>/{target,staging}` and aggregated
  `<output_dir>/legal-info/`.

  Output goes to a fresh temp dir per build — BR's `.config` is a single
  global file per build tree, so we don't share output across packages
  with different configs. Buildroot's `BR2_DL_DIR` cache handles
  source-tarball reuse across builds; the per-build `output/` is cheap
  to discard.

  Currently Linux-only. macOS and other hosts will be supported via a
  Docker wrapper in a later phase.
  """

  alias NBPR.Buildroot.Source

  @doc """
  Builds `br_package` against `defconfig_text` using the BR tree at
  `br_source`. Returns the absolute path to the build's `O=<dir>` output.

  The caller owns the output dir's lifetime — typically harvested
  immediately afterwards by `NBPR.Buildroot.Harvest` (Phase 4.4) and then
  removed.
  """
  @spec build!(Path.t(), String.t(), String.t()) :: Path.t()
  def build!(br_source, defconfig_text, br_package)
      when is_binary(br_source) and is_binary(defconfig_text) and is_binary(br_package) do
    ensure_linux!()

    output_dir = make_output_dir!(br_package)
    File.write!(Path.join(output_dir, ".config"), defconfig_text)

    env = build_env()

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

  defp make_output_dir!(br_package) do
    dir =
      Path.join([
        System.tmp_dir!(),
        "nbpr_br_build_#{br_package}_#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(dir)
    dir
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
