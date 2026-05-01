defmodule NBPR.Buildroot.Harvest do
  @moduledoc """
  Locates per-package Buildroot output and packages it as an
  `NBPR.Pack.sources()` map for hand-off to `NBPR.Pack.pack!/3`.

  After `NBPR.Buildroot.Build.build!/3` runs `make <pkg>-rebuild` with
  `BR2_PER_PACKAGE_DIRECTORIES=y`, the per-package output is at:

      <output_dir>/per-package/<br_package>/
        ├── target/        # files installed into the rootfs
        ├── staging/       # sysroot-side (headers, .so symlinks for NIFs)
        └── host/          # build-host artefacts (skipped — not for distribution)

  Harvest returns the appropriate `:target` and `:staging` source paths
  if they exist; legal-info aggregation, source-tarball collection, and
  `rootfs/` categorisation (for kmod files etc.) are not yet automated.
  """

  @doc """
  Returns the `NBPR.Pack.sources()` map for `br_package` under `output_dir`.

  Raises if the per-package output directory is missing or empty — usually
  a sign that `BR2_PER_PACKAGE_DIRECTORIES=y` wasn't enabled or the build
  itself didn't run.
  """
  @spec harvest!(Path.t(), String.t()) :: NBPR.Pack.sources()
  def harvest!(output_dir, br_package)
      when is_binary(output_dir) and is_binary(br_package) do
    pp_dir = Path.join([output_dir, "per-package", br_package])

    unless File.dir?(pp_dir) do
      raise """
      no per-package output found at #{pp_dir}.

      Likely causes:
        - The build never ran (`make #{br_package}-rebuild` failed silently)
        - `BR2_PER_PACKAGE_DIRECTORIES=y` is not set in the defconfig
      """
    end

    sources =
      %{}
      |> maybe_add(:target, Path.join(pp_dir, "target"))
      |> maybe_add(:staging, Path.join(pp_dir, "staging"))
      |> maybe_add(:legal_info, Path.join(pp_dir, "legal-info"))

    if map_size(sources) == 0 do
      raise "per-package output for #{br_package} contains neither target/ nor staging/"
    end

    sources
  end

  defp maybe_add(map, key, path) do
    if File.dir?(path), do: Map.put(map, key, path), else: map
  end
end
