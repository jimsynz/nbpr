defmodule NBPR.Linux.Builder do
  @moduledoc """
  Source-builds a kernel-replacement artefact: rebuilds the active Nerves
  system's Linux kernel with the user's config fragments and patches layered
  on, then packs the kernel image, device trees, and in-tree modules into the
  canonical artefact tarball.

  Pipeline:

    1. Ensure the patched Buildroot source tree (shared with userspace builds).
    2. Ensure the active system's source tree (for its `nerves_defconfig`).
    3. Resolve the user's `:nbpr_linux` fragments/patches and stage them.
    4. Render a defconfig pinning the system's kernel version and merging in the
       fragment/patch lines, then `make olddefconfig && make linux`.
    5. Harvest `images/` (→ `boot/`) and `lib/modules` (→ `rootfs/`).
    6. Pack the tarball.

  ## Build environment

  Mirrors the userspace builder: runs natively when inside the canonical Nerves
  build env (`mix nerves.system.shell`), and otherwise inside the
  `nerves_system_br` container via `NBPR.Buildroot.Docker`. The container path
  stages the user's fragment/patch files under the bind-mounted extract dir so
  the rendered defconfig's absolute paths resolve inside the container.
  """

  alias NBPR.Buildroot
  alias NBPR.Buildroot.{Docker, Source, SystemSource}
  alias NBPR.Linux.{Config, Defconfig, Harvest}
  alias NBPR.Pack

  @doc """
  Builds the kernel artefact for `inputs`, writing the tarball into
  `output_dir` and returning its absolute path.
  """
  @spec build!(NBPR.Package.t(), NBPR.Artifact.build_inputs(), Path.t()) :: Path.t()
  def build!(%NBPR.Package{kind: :kernel}, %{} = inputs, output_dir) when is_binary(output_dir) do
    File.mkdir_p!(output_dir)

    Mix.shell().info(
      "[nbpr] source-building kernel for #{inputs.system_app} #{inputs.system_version}"
    )

    {:ok, nerves_system_br_path} = Buildroot.nerves_system_br_path()
    {:ok, br_version} = Buildroot.br_version(nerves_system_br_path)
    {:ok, patches_dir} = Buildroot.patches_path(nerves_system_br_path)

    br_source = Source.ensure!(br_version, patches_dir)
    system_source = SystemSource.ensure!(inputs.system_app, inputs.system_version)
    base_defconfig = read_system_defconfig!(system_source)
    config = Config.resolve(String.to_existing_atom(inputs.package_name))

    out = kernel_output_dir(inputs.system_app, br_version)

    env = [
      {"BR2_DL_DIR", Source.download_dir()},
      {"NERVES_DEFCONFIG_DIR", system_source},
      {"BR2_EXTERNAL", nerves_system_br_path}
    ]

    harvest_src =
      if Docker.in_canonical_env?() do
        native_build!(br_source, out, base_defconfig, config, env)
      else
        docker_build!(br_source, out, inputs, br_version, base_defconfig, config, env)
      end

    harvest_root = harvest_src <> ".harvest"
    File.rm_rf!(harvest_root)
    File.mkdir_p!(harvest_root)
    sources = Harvest.collect!(harvest_src, harvest_root)

    Pack.pack!(inputs, sources, output_dir)
  end

  @doc """
  The dedicated per-(system, BR-version) kernel build dir. Kept separate from
  the userspace `stable_output_dir/2` so `images/` only ever holds the kernel's
  own outputs (no full-system cruft to confuse the harvest).
  """
  @spec kernel_output_dir(atom(), String.t()) :: Path.t()
  def kernel_output_dir(system_app, br_version)
      when is_atom(system_app) and is_binary(br_version) do
    Path.join([data_dir(), "nbpr", "build-linux", "#{system_app}-#{br_version}"])
  end

  # Native (canonical env): `out` is a host dir we build into and harvest from.
  defp native_build!(br_source, out, base_defconfig, config, env) do
    ensure_linux!()
    File.mkdir_p!(out)

    {fragments, patches} = stage_config!(config, Path.join(out, "nbpr-config"))
    File.write!(Path.join(out, ".config"), Defconfig.render(base_defconfig, fragments, patches))

    run_make!(br_source, out, env, ["olddefconfig"])
    run_make!(br_source, out, env, ["linux"])

    out
  end

  # Docker: `out` is the in-container volume mount path; fragments/patches and
  # the harvested outputs live under the bind-mounted `extract_dir`.
  defp docker_build!(br_source, out, inputs, br_version, base_defconfig, config, env) do
    extract_dir = out <> ".extract"
    {fragments, patches} = stage_config!(config, Path.join(extract_dir, "nbpr-config"))
    defconfig = Defconfig.render(base_defconfig, fragments, patches)

    Docker.build_kernel!(
      br_source: br_source,
      build_path: out,
      volume: Docker.volume_name("#{inputs.system_app}-#{br_version}-linux"),
      extract_dir: extract_dir,
      defconfig_text: defconfig,
      env: env,
      extra_mounts: [Mix.Project.deps_path()]
    )
  end

  # Copies the user's fragments/patches into a bind-mountable staging dir so
  # Buildroot reads them from a stable absolute path (valid both natively and,
  # since the dir is bind-mounted at the same path, inside the container).
  defp stage_config!(%{fragments: fragments, patches: patches}, dir) do
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    {stage_files!(fragments, Path.join(dir, "fragments")),
     stage_files!(patches, Path.join(dir, "patches"))}
  end

  defp stage_files!([], _dir), do: []

  defp stage_files!(paths, dir) do
    File.mkdir_p!(dir)

    Enum.map(paths, fn src ->
      dest = Path.join(dir, Path.basename(src))
      File.cp!(src, dest)
      dest
    end)
  end

  defp read_system_defconfig!(system_source) do
    path = Path.join(system_source, "nerves_defconfig")
    unless File.regular?(path), do: Mix.raise("system defconfig not found at #{path}")
    File.read!(path)
  end

  defp run_make!(cwd, output_dir, env, targets) do
    args = ["O=#{output_dir}" | targets]
    Mix.shell().info("[nbpr] running: make #{Enum.join(args, " ")}")

    case System.cmd("make", args,
           cd: cwd,
           env: env,
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {_, status} ->
        Mix.raise("Buildroot `make #{Enum.join(targets, " ")}` failed (exit #{status})")
    end
  end

  defp ensure_linux! do
    case :os.type() do
      {:unix, :linux} ->
        :ok

      other ->
        Mix.raise("native kernel build requires Linux; detected #{inspect(other)}")
    end
  end

  defp data_dir do
    cond do
      dir = System.get_env("NERVES_ARTIFACTS_DIR") ->
        dir

      true ->
        base = System.get_env("XDG_DATA_HOME") || Path.join(System.user_home!(), ".local/share")
        Path.join(base, "nerves")
    end
  end
end
