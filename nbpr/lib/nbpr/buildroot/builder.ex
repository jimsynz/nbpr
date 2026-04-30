defmodule NBPR.Buildroot.Builder do
  @moduledoc """
  Source-builds an NBPR package artefact tarball end-to-end.

  Driven from both `Mix.Tasks.Nbpr.Build` (CLI) and `Mix.Tasks.Nbpr.Fetch`'s
  fallback path (when no prebuilt artefact is published for the active
  (system, system_version, build_opts) tuple).

  Pipeline:

    1. Discover `deps/nerves_system_br/` and read the pinned BR version.
    2. Ensure the patched BR source tree at
       `$NERVES_DATA_DIR/nbpr/buildroot/<version>/`.
    3. Render a defconfig that layers the package + its `build_opts` on top
       of the active system's `nerves_defconfig`.
    4. Run BR (`<pkg>-dirclean && <pkg>`) against a stable per-(system,
       BR-version) output dir, in Docker on non-Linux hosts.
    5. Filter per-package output via BR's files-list (runtime-only).
    6. Pack into the canonical artefact tarball at `output_dir/`.

  Returns the absolute path to the produced tarball.
  """

  alias NBPR.Buildroot
  alias NBPR.Buildroot.{Build, Defconfig, Harvest, Source, SystemSource}
  alias NBPR.Pack

  @doc """
  Builds the artefact for `pkg` against `inputs.system_app`/`system_version`,
  with `inputs.build_opts` applied. Writes the tarball into `output_dir` and
  returns its absolute path.

  `inputs` is the standard `NBPR.Artifact.build_inputs/0` map (the same one
  used for cache-key/manifest computation in the fetch path).
  """
  @spec build!(NBPR.Package.t(), NBPR.Artifact.build_inputs(), Path.t()) :: Path.t()
  def build!(%NBPR.Package{} = pkg, %{} = inputs, output_dir) when is_binary(output_dir) do
    File.mkdir_p!(output_dir)

    Mix.shell().info("[nbpr] source-building #{inputs.package_name} #{inputs.package_version}")

    br_source = ensure_br_source!()

    system_source_path =
      SystemSource.ensure!(inputs.system_app, inputs.system_version)

    {:ok, nerves_system_br_path} = Buildroot.nerves_system_br_path()
    {:ok, br_version} = Buildroot.br_version(nerves_system_br_path)

    output_dir_br = stable_output_dir(inputs.system_app, br_version)
    defconfig_text = render_defconfig!(pkg, system_source_path, inputs.build_opts)

    extra_env = [
      {"NERVES_DEFCONFIG_DIR", system_source_path},
      {"BR2_EXTERNAL", nerves_system_br_path}
    ]

    deps_path = Mix.Project.deps_path()

    harvest_dir =
      Build.build!(br_source, output_dir_br, defconfig_text, pkg.br_package, extra_env,
        extra_mounts: [deps_path]
      )

    sources = Harvest.harvest!(harvest_dir, pkg.br_package)
    Pack.pack!(inputs, sources, output_dir)
  end

  @doc """
  Returns the stable per-(system, BR-version) BR output dir. Reusing across
  builds keeps the toolchain extraction, host-skeleton, and unchanged packages
  cached; `make olddefconfig` reconciles defconfig drift.
  """
  @spec stable_output_dir(atom(), String.t()) :: Path.t()
  def stable_output_dir(system_app, br_version)
      when is_atom(system_app) and is_binary(br_version) do
    Path.join([data_dir(), "nbpr", "build", "#{system_app}-#{br_version}"])
  end


  defp data_dir do
    cond do
      dir = System.get_env("NERVES_ARTIFACTS_DIR") ->
        dir

      true ->
        base =
          System.get_env("XDG_DATA_HOME") ||
            Path.join(System.user_home!(), ".local/share")

        Path.join(base, "nerves")
    end
  end

  defp render_defconfig!(pkg, system_source_path, build_opts) do
    sys_defconfig = Path.join(system_source_path, "nerves_defconfig")

    unless File.regular?(sys_defconfig) do
      Mix.raise("system defconfig not found at #{sys_defconfig}")
    end

    Defconfig.render!(pkg, sys_defconfig, build_opts)
  end

  defp ensure_br_source! do
    {:ok, system_br_path} = require_nerves_system_br!()
    {:ok, br_version} = require_br_version!(system_br_path)
    {:ok, patches_dir} = require_patches!(system_br_path)

    Mix.shell().info(
      "[nbpr] ensuring BR #{br_version} source cache (one-time download if needed)"
    )

    Source.ensure!(br_version, patches_dir)
  end

  defp require_nerves_system_br! do
    case Buildroot.nerves_system_br_path() do
      {:ok, path} ->
        {:ok, path}

      {:error, _} ->
        Mix.raise(
          "deps/nerves_system_br not found; run `mix deps.get` first or check your mix.exs"
        )
    end
  end

  defp require_br_version!(system_br_path) do
    case Buildroot.br_version(system_br_path) do
      {:ok, version} -> {:ok, version}
      {:error, reason} -> Mix.raise("could not read BR version: #{inspect(reason)}")
    end
  end

  defp require_patches!(system_br_path) do
    case Buildroot.patches_path(system_br_path) do
      {:ok, dir} -> {:ok, dir}
      {:error, _} -> Mix.raise("BR patches dir missing at #{system_br_path}/patches/buildroot")
    end
  end
end
