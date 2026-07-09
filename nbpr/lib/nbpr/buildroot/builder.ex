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

  `inputs` is the standard `t:NBPR.Artifact.build_inputs/0` map (the same one
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

    external_path = package_external_path(pkg)

    # For a vendored package, the package's own BR external tree is appended to
    # `BR2_EXTERNAL` (colon-separated) alongside `nerves_system_br`, so its
    # `package/<name>/` definitions and `BR2_PACKAGE_*` symbols resolve.
    br2_external =
      [nerves_system_br_path, external_path]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")

    extra_env = [
      {"NERVES_DEFCONFIG_DIR", system_source_path},
      {"BR2_EXTERNAL", br2_external}
    ]

    deps_path = Mix.Project.deps_path()
    extra_mounts = Enum.reject([deps_path, external_path], &is_nil/1)

    merged = merge_root!(output_dir, inputs)

    # Build each Buildroot target (one for mainline, several for a vendored
    # tree built in dependency order) and merge their per-package outputs into
    # a single staging tree. Buildroot resolves each target's own dependencies
    # — e.g. a kernel-module package pulls in and builds `linux` — so no
    # special kernel handling is needed here.
    for target <- NBPR.Package.br_targets(pkg) do
      harvest_dir =
        Build.build!(br_source, output_dir_br, defconfig_text, target, extra_env,
          extra_mounts: extra_mounts
        )

      harvest_dir
      |> Harvest.harvest!(target)
      |> merge_sources!(merged)
    end

    sources = categorise!(merged, pkg.rootfs_paths)
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

  defp package_external_path(%NBPR.Package{br_external_path: nil}), do: nil

  defp package_external_path(%NBPR.Package{br_external_path: rel, name: name}) do
    app = String.to_atom("nbpr_#{name}")

    base =
      case Map.get(Mix.Project.deps_paths(), app) do
        nil ->
          Mix.raise(
            "could not locate the source directory for #{app}; it must be a " <>
              "dependency of the current project for its vendored Buildroot tree to resolve"
          )

        path ->
          path
      end

    abs = Path.expand(Path.join(base, rel))

    unless File.dir?(abs) do
      Mix.raise("vendored Buildroot external tree for #{app} not found at #{abs}")
    end

    abs
  end

  # Fresh per-build staging tree where each target's harvested output is
  # overlaid. Lives under output_dir so the final rename in Pack stays on one
  # filesystem.
  defp merge_root!(output_dir, inputs) do
    root = Path.join(output_dir, ".merged-#{inputs.package_name}")
    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end

  defp merge_sources!(sources, merged_root) do
    Enum.each(sources, fn {key, src} ->
      merge_tree!(src, Path.join(merged_root, dest_name(key)))
    end)
  end

  defp dest_name(:target), do: "target"
  defp dest_name(:staging), do: "staging"
  defp dest_name(:rootfs), do: "rootfs"
  defp dest_name(:legal_info), do: "legal-info"

  # Recursive directory overlay that preserves symlinks and merges into any
  # existing tree (unlike `File.cp_r!/2`, which nests when the destination
  # already exists).
  defp merge_tree!(src, dst) do
    File.mkdir_p!(dst)

    Enum.each(File.ls!(src), fn entry ->
      s = Path.join(src, entry)
      d = Path.join(dst, entry)

      case File.lstat!(s) do
        %File.Stat{type: :directory} ->
          merge_tree!(s, d)

        %File.Stat{type: :symlink} ->
          File.mkdir_p!(Path.dirname(d))
          _ = File.rm(d)
          {:ok, link_target} = File.read_link(s)
          File.ln_s!(link_target, d)

        _ ->
          File.mkdir_p!(Path.dirname(d))
          _ = File.rm(d)
          File.cp!(s, d)
      end
    end)
  end

  # Splits the merged tree into the `NBPR.Pack.sources()` categories, routing
  # the package's `rootfs_paths` subtrees (firmware, NIF-linked libs) out of
  # `target/` (→ priv) into `rootfs/` (→ the real rootfs).
  defp categorise!(merged_root, rootfs_paths) do
    target_dir = Path.join(merged_root, "target")
    rootfs_dir = Path.join(merged_root, "rootfs")

    Enum.each(rootfs_paths, fn rel ->
      from = Path.join(target_dir, rel)

      if File.dir?(from) do
        to = Path.join(rootfs_dir, rel)
        File.mkdir_p!(Path.dirname(to))
        File.rename!(from, to)
      end
    end)

    %{}
    |> put_if_dir(:target, target_dir)
    |> put_if_dir(:staging, Path.join(merged_root, "staging"))
    |> put_if_dir(:rootfs, rootfs_dir)
    |> put_if_dir(:legal_info, Path.join(merged_root, "legal-info"))
  end

  defp put_if_dir(map, key, path) do
    if File.dir?(path), do: Map.put(map, key, path), else: map
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
