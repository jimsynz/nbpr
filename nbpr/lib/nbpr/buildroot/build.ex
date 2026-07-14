defmodule NBPR.Buildroot.Build do
  @moduledoc """
  Drives a per-package Buildroot build.

  Given a patched BR source tree (from `NBPR.Buildroot.Source.ensure!/2`),
  a stable output dir, a rendered defconfig (from
  `NBPR.Buildroot.Defconfig.render!/3`), and a Buildroot package name,
  produces per-package output at
  `<output_dir>/per-package/<pkg>/{target,staging}`.

  The actual build is delegated to a `NBPR.Buildroot.Backend` — native `make`
  inside the canonical env, or a container runtime (docker/podman) elsewhere.
  `NBPR.Buildroot.Backend.select/0` picks the appropriate one. This module owns
  the shared build env and the `spec` hand-off.

  ## Output dir reuse

  The caller supplies the `output_dir`. For interactive speed, use a
  stable per-(system, BR-version) path — the toolchain extraction,
  host-skeleton, host-fakedate, and other shared steps then survive
  between invocations and only the package being rebuilt actually
  compiles. `make olddefconfig` reconciles defconfig drift across
  builds (e.g. enabling a different `BR2_PACKAGE_*=y`).
  """

  alias NBPR.Buildroot.Backend
  alias NBPR.Buildroot.Source

  @doc """
  Builds `br_package` against `defconfig_text` using the BR tree at
  `br_source`, with output going to `output_dir`. Returns the harvest dir
  (containing `per-package/<br_package>/`), ready for
  `NBPR.Buildroot.Harvest.harvest!/2`.

  `extra_env` is merged into the make invocation's env. Use it to pass
  Nerves-specific variables that the system's defconfig references —
  most importantly `NERVES_DEFCONFIG_DIR` (so `BR2_GLOBAL_PATCH_DIR`
  resolves) and `BR2_EXTERNAL` (so the system's BR external tree is
  visible).

  `output_dir` is created if missing. Existing contents are preserved —
  this is the design — so subsequent builds reuse the toolchain,
  skeleton, and other unchanging packages. To force from-scratch,
  `File.rm_rf!(output_dir)` before calling.

  `opts` accepts `:extra_mounts` — additional host paths a container backend
  bind-mounts at the same path inside the container.
  """
  @spec build!(Path.t(), Path.t(), String.t(), String.t(), [{String.t(), String.t()}], keyword()) ::
          Path.t()
  def build!(br_source, output_dir, defconfig_text, br_package, extra_env \\ [], opts \\ [])
      when is_binary(br_source) and is_binary(output_dir) and is_binary(defconfig_text) and
             is_binary(br_package) and is_list(extra_env) do
    spec = %{
      br_source: br_source,
      output_dir: output_dir,
      defconfig_text: defconfig_text,
      br_package: br_package,
      env: build_env() ++ extra_env,
      extra_mounts: Keyword.get(opts, :extra_mounts, [])
    }

    Backend.select().build!(spec)
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
end
