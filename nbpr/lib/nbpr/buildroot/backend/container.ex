defmodule NBPR.Buildroot.Backend.Container do
  @moduledoc """
  Shared runner for the container-based backends (`NBPR.Buildroot.Backend.Docker`,
  `NBPR.Buildroot.Backend.Podman`, and future CLI-compatible runtimes).

  Runs a Buildroot build inside the canonical Nerves build container
  (`ghcr.io/nerves-project/nerves_system_br:latest`). The in-container bash
  script is identical across runtimes — only the outer invocation differs
  (which executable, and whether the extracted output must be chowned back to
  the host user), so the concrete backends are thin wrappers that call
  `build!/2` with those two knobs.

  ## Why

  The containerised env avoids subtle host-vs-canonical differences in
  toolchain wrappers, sysroot paths, and ABI flags when `mix nbpr.build` is
  invoked outside `mix nerves.system.shell`.

  ## Storage layout

  BR's per-package mode rsyncs files between intra-build directories with
  `--hard-links`. macOS Docker bind mounts (osxfs / VirtioFS) don't support
  hardlinks, so the BR build dir cannot be a bind mount on those hosts.

  Instead the build dir lives in a **named volume** keyed by
  `(system, BR version)`:

    - `nbpr_build_<system>_<br_version>` — persistent across runs
    - mounted inside the container at the same path the host would use
      (so env vars like `BR2_DL_DIR`, `NERVES_DEFCONFIG_DIR` work
      without path translation)
    - hardlinks work because volumes are native Linux filesystems

  After `make` succeeds, the per-package output is copied from the volume to a
  host bind-mounted dir so `NBPR.Buildroot.Harvest` and `NBPR.Pack` (both
  running on the host) can read it.

  ## Cleanup

  Volumes persist across runs. Periodically remove them (`docker volume rm` /
  `podman volume rm`), or add a `mix nbpr.cache.clean` task later.
  """

  @image "ghcr.io/nerves-project/nerves_system_br:latest"

  @doc """
  Returns `true` when `executable` is on PATH.
  """
  @spec available?(String.t()) :: boolean()
  def available?(executable) when is_binary(executable) do
    System.find_executable(executable) != nil
  end

  @doc """
  Runs the BR build for `spec` inside a container using `executable`.

  Options:
    - `:executable` — the container runtime to invoke (e.g. `"docker"`,
      `"podman"`). Must be CLI-compatible for the `run`/`-v`/`-e`/`--user`
      subset used here.
    - `:chown_output?` — whether to `chown -R` the extracted output back to the
      host user inside the container. Needed under docker / rootful podman
      (container runs as real root); harmful under rootless podman (which
      already writes host-owned files).

  Returns the harvest dir (`spec.output_dir <> ".extract"`), containing
  `per-package/<br_package>/`, ready for `NBPR.Buildroot.Harvest.harvest!/2`.
  """
  @spec build!(NBPR.Buildroot.Backend.spec(), keyword()) :: Path.t()
  def build!(spec, opts) do
    executable = Keyword.fetch!(opts, :executable)
    chown_output? = Keyword.fetch!(opts, :chown_output?)

    runtime =
      System.find_executable(executable) ||
        raise "container runtime #{inspect(executable)} not found on PATH"

    build_path = spec.output_dir
    volume = volume_name(Path.basename(build_path))
    extract_dir = build_path <> ".extract"

    File.mkdir_p!(extract_dir)
    defconfig_host_file = Path.join(extract_dir, "_nbpr_defconfig.in")
    File.write!(defconfig_host_file, spec.defconfig_text)

    bind_mount_paths =
      [extract_dir, spec.br_source | spec.extra_mounts]
      |> Enum.concat(env_paths(spec.env))
      |> Enum.uniq()
      |> Enum.filter(&File.exists?/1)

    bash_script =
      build_script(
        build_path,
        defconfig_host_file,
        spec.br_source,
        spec.br_package,
        extract_dir,
        chown_output?
      )

    # The image's default user is `nerves`, not root, so without `--user 0:0`
    # we can't write to the freshly-created (root-owned) named volume. Run
    # as root; under docker/rootful podman the script then `chown -R`s the
    # extracted output back to the host user (no-op under rootless podman).
    host_uid = user_id()
    host_gid = group_id()

    run_args =
      ["run", "--rm", "--user", "0:0"] ++
        ["-v", "#{volume}:#{build_path}"] ++
        Enum.flat_map(bind_mount_paths, fn p -> ["-v", "#{p}:#{p}"] end) ++
        env_args(spec.env) ++
        ["-e", "HOST_UID=#{host_uid}", "-e", "HOST_GID=#{host_gid}"] ++
        [@image, "bash", "-c", bash_script]

    Mix.shell().info("[nbpr] running BR build in #{Path.basename(runtime)} (volume #{volume})")

    case System.cmd(runtime, run_args,
           stderr_to_stdout: true,
           into: IO.stream(:stdio, :line)
         ) do
      {_, 0} ->
        extract_dir

      {_, status} ->
        raise "Buildroot build (in #{Path.basename(runtime)}) failed with exit status #{status}"
    end
  end

  @doc false
  @spec volume_name(String.t()) :: String.t()
  def volume_name(slug) when is_binary(slug) do
    "nbpr_build_" <> sanitise_volume_name(slug)
  end

  defp sanitise_volume_name(s) do
    String.replace(s, ~r/[^A-Za-z0-9_-]/, "_")
  end

  defp build_script(build_path, defconfig_host, br_source, br_package, extract_dir, do_chown) do
    pp_src = "#{build_path}/per-package/#{br_package}"
    pp_dst = "#{extract_dir}/per-package/#{br_package}"

    """
    set -euo pipefail

    cp #{shell_quote(defconfig_host)} #{shell_quote(build_path)}/.config

    cd #{shell_quote(br_source)}
    make O=#{shell_quote(build_path)} olddefconfig

    # `<pkg>-dirclean && <pkg>` (not `<pkg>-rebuild`) so BR snapshots the
    # before/after target trees and writes a populated `.files-list.txt` /
    # `.files-list-staging.txt`. `<pkg>-rebuild` skips the snapshot step,
    # leaving the lists empty. Dirclean only wipes `per-package/<pkg>/`;
    # the toolchain, host tools, and other deps stay cached.
    make O=#{shell_quote(build_path)} #{shell_quote("#{br_package}-dirclean")}
    make O=#{shell_quote(build_path)} #{shell_quote(br_package)}

    # Collect upstream licence files (best-effort — packages without
    # `FOO_LICENSE_FILES` declared get no output here).
    make O=#{shell_quote(build_path)} #{shell_quote("#{br_package}-legal-info")} || true

    # Use BR's files-list to copy only THIS package's contribution out of the
    # merged per-package sysroot — without this, we'd ship the BR target
    # skeleton (libc, libstdc++, /etc/passwd, ...) plus every transitive
    # dep's files in every artefact.
    #
    # `host/` is also copied by the merge but never consumed by Harvest, and
    # it carries the toolchain's full kernel-header tree which has
    # case-only-distinct names (e.g. `xt_MARK.h` vs `xt_mark.h`) that
    # collide on case-insensitive host filesystems (default APFS on macOS).
    rm -rf #{shell_quote(pp_dst)}
    mkdir -p #{shell_quote(pp_dst)}/target #{shell_quote(pp_dst)}/staging

    BUILD_DIR=$(ls -d #{shell_quote(build_path)}/build/#{br_package}-*/ 2>/dev/null | head -1)
    BUILD_DIR="${BUILD_DIR%/}"
    if [ -z "$BUILD_DIR" ] || [ ! -d "$BUILD_DIR" ]; then
      echo "could not locate build dir for #{br_package} under #{build_path}/build/" >&2
      exit 1
    fi

    copy_listed() {
      local src_root="$1" dst_root="$2" list="$3" keep_dev="${4:-0}"
      [ -f "$list" ] || return 0

      # files-list format: `<pkg>,./<path>` (one per line). Strip the
      # `<pkg>,` prefix to get the relative path.
      while IFS= read -r line; do
        path="${line#*,}"

        # Headers/pkg-config are dropped from the runtime (target) tree but
        # kept in staging (keep_dev=1) so consumer NIFs can cross-compile.
        if [ "$keep_dev" != "1" ]; then
          case "$path" in
            ./usr/include/*|./usr/lib/pkgconfig/*) continue ;;
          esac
        fi

        case "$path" in
          # Docs/manpages and libtool archives are never shipped.
          ./usr/share/doc/*|./usr/share/man/*|./usr/share/info/*) continue ;;
          *.la) continue ;;
          *) ;;
        esac

        rel="${path#./}"
        src_path="$src_root/$rel"
        dst_path="$dst_root/$rel"
        # Warn (don't silently drop) if the files-list names a file that isn't
        # present at copy time — a silent drop ships an incomplete artefact.
        if [ ! -e "$src_path" ] && [ ! -L "$src_path" ]; then
          echo "[nbpr] WARNING: listed file missing at harvest time, skipping: $rel" >&2
          continue
        fi

        mkdir -p "$(dirname "$dst_path")"
        cp -aP "$src_path" "$dst_path"
      done < "$list"
    }

    copy_listed "#{pp_src}/target" "#{pp_dst}/target" "$BUILD_DIR/.files-list.txt"

    # With a Nerves (external) toolchain, STAGING_DIR is the toolchain sysroot
    # under host/<tuple>/sysroot, not a separate staging/ dir — that's where the
    # files-list-staging paths are rooted. Fall back to staging/ otherwise.
    STAGING_SRC=$(ls -d #{pp_src}/host/*/sysroot 2>/dev/null | head -1 || true)
    [ -n "$STAGING_SRC" ] || STAGING_SRC="#{pp_src}/staging"
    copy_listed "$STAGING_SRC" "#{pp_dst}/staging" "$BUILD_DIR/.files-list-staging.txt" 1

    # Drop empty staging dir so Harvest's existence check skips it cleanly.
    if [ -z "$(ls -A "#{pp_dst}/staging" 2>/dev/null)" ]; then
      rmdir "#{pp_dst}/staging"
    fi

    #{NBPR.Buildroot.Finalize.script("#{pp_dst}/target", "#{pp_src}/host/bin", "#{build_path}/.config")}

    # Concatenate upstream licence files into a single `legal-info/<pkg>.txt`,
    # matching the canonical artefact layout. Empty / missing licences-dir is
    # not fatal (some packages don't declare `FOO_LICENSE_FILES`).
    # `|| true`: under `set -euo pipefail` a non-matching glob makes `ls` exit
    # non-zero and (via pipefail) aborts the script. A package with no licence
    # files (e.g. a proprietary firmware blob) legitimately has no licences dir.
    LICENSE_DIR=$(ls -d #{shell_quote(build_path)}/legal-info/licenses/#{br_package}-*/ 2>/dev/null | head -1 || true)
    LICENSE_DIR="${LICENSE_DIR%/}"
    if [ -n "$LICENSE_DIR" ] && [ -d "$LICENSE_DIR" ]; then
      mkdir -p #{shell_quote(pp_dst)}/legal-info
      LICENSE_FILES=$(find "$LICENSE_DIR" -type f | sort)
      if [ -n "$LICENSE_FILES" ]; then
        # `awk` join with two blank lines between files, matching the
        # reference artefact's separator.
        awk 'FNR==1 && NR>1 { print ""; print ""; print "" } { print }' \\
          $LICENSE_FILES > #{shell_quote(pp_dst)}/legal-info/#{br_package}.txt
      fi
    fi

    #{chown_cmd(do_chown, extract_dir)}
    """
  end

  # Under docker / rootful podman the container runs as real root, so the
  # extracted output is root-owned on the host and must be chowned back to the
  # host user for the Mix task to read it. Under rootless podman container-root
  # already maps to the host user, so the files are host-owned and a chown would
  # instead map into the subuid range — skip it.
  defp chown_cmd(false, _extract_dir),
    do: "# rootless: output already host-owned, no chown needed"

  defp chown_cmd(true, extract_dir) do
    """
    # Make the extracted output owned by the host user so the Mix task
    # (running as that user) can read it. The volume itself stays root-owned
    # — that's fine, we never read it directly from the host.
    chown -R "${HOST_UID}:${HOST_GID}" #{shell_quote(extract_dir)}\
    """
  end

  defp shell_quote(s) do
    # Single-quote with embedded quote escaping for paths in bash scripts.
    "'" <> String.replace(s, "'", "'\\''") <> "'"
  end

  defp env_args(env), do: Enum.flat_map(env, fn {k, v} -> ["-e", "#{k}=#{v}"] end)

  defp env_paths(env) do
    for {_k, v} <- env, is_binary(v), String.starts_with?(v, "/"), File.exists?(v), do: v
  end

  defp user_id do
    {out, 0} = System.cmd("id", ["-u"])
    String.trim(out)
  end

  defp group_id do
    {out, 0} = System.cmd("id", ["-g"])
    String.trim(out)
  end
end
