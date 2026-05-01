defmodule NBPR.Buildroot.Docker do
  @moduledoc """
  Runs a Buildroot build inside the canonical Nerves build container
  (`ghcr.io/nerves-project/nerves_system_br:latest`).

  ## Why

  Phase 4.5 fallback for when `mix nbpr.build` is invoked outside
  `mix nerves.system.shell` — the containerised env avoids subtle
  host-vs-canonical differences in toolchain wrappers, sysroot paths,
  and ABI flags.

  ## Storage layout

  BR's per-package mode rsyncs files between intra-build directories with
  `--hard-links`. macOS Docker bind mounts (osxfs / VirtioFS) don't support
  hardlinks, so the BR build dir cannot be a bind mount on those hosts.

  Instead the build dir lives in a **named Docker volume** keyed by
  `(system, BR version)`:

    - `nbpr_build_<system>_<br_version>` — persistent across runs
    - mounted inside the container at the same path the host would use
      (so env vars like `BR2_DL_DIR`, `NERVES_DEFCONFIG_DIR` work
      without path translation)
    - hardlinks work because volumes are native Linux filesystems

  After `make` succeeds, the per-package output is `cp -r`'d from the
  volume to a host bind-mounted dir so `NBPR.Buildroot.Harvest` and
  `NBPR.Pack` (both running on the host) can read it.

  ## Cleanup

  Volumes persist across runs. Periodically `docker volume rm` them, or
  add a `mix nbpr.cache.clean` task later.
  """

  @image "ghcr.io/nerves-project/nerves_system_br:latest"

  @doc """
  Returns `true` when `docker` is on PATH.
  """
  @spec available?() :: boolean()
  def available?, do: System.find_executable("docker") != nil

  @doc """
  Returns `true` when we're already running inside a Nerves canonical
  build env (so re-invoking under Docker would be redundant).

  Detection: `IN_NERVES_DEV_SHELL=1` env var, or `/home/nerves/project`
  exists on disk (the standard working dir in nerves_system_br images).
  """
  @spec in_canonical_env?() :: boolean()
  def in_canonical_env? do
    System.get_env("IN_NERVES_DEV_SHELL") == "1" or File.dir?("/home/nerves/project")
  end

  @doc """
  Runs the BR build inside a container.

  Returns the host path containing the per-package extraction
  (`<extract_dir>/per-package/<br_package>/{target,staging}/...`),
  ready for `NBPR.Buildroot.Harvest.harvest!/2`.

  Required opts:
    - `:br_source` — path to the patched BR tree on host
    - `:build_path` — the path the named volume is mounted at (matches what
      env vars reference)
    - `:volume` — Docker volume name for the build cache
    - `:extract_dir` — host bind-mount path where per-package output is copied
    - `:defconfig_text` — full defconfig content to write into the build dir
    - `:br_package` — BR package name (e.g. `"jq"`)
    - `:env` — list of `{key, value}` env vars to pass through
    - `:extra_mounts` — additional host paths to bind-mount at the same path
      inside the container
  """
  @spec build!(keyword()) :: Path.t()
  def build!(opts) do
    ensure_available!()

    br_source = Keyword.fetch!(opts, :br_source)
    build_path = Keyword.fetch!(opts, :build_path)
    volume = Keyword.fetch!(opts, :volume)
    extract_dir = Keyword.fetch!(opts, :extract_dir)
    defconfig_text = Keyword.fetch!(opts, :defconfig_text)
    br_package = Keyword.fetch!(opts, :br_package)
    env = Keyword.get(opts, :env, [])
    extra_mounts = Keyword.get(opts, :extra_mounts, [])

    File.mkdir_p!(extract_dir)
    defconfig_host_file = Path.join(extract_dir, "_nbpr_defconfig.in")
    File.write!(defconfig_host_file, defconfig_text)

    bind_mount_paths =
      [extract_dir, br_source | extra_mounts]
      |> Enum.concat(env_paths(env))
      |> Enum.uniq()
      |> Enum.filter(&File.exists?/1)

    bash_script =
      build_script(build_path, defconfig_host_file, br_source, br_package, extract_dir)

    # The image's default user is `nerves`, not root, so without `--user 0:0`
    # we can't write to the freshly-created (root-owned) named volume. Run
    # as root, then `chown -R` the extracted output to the host user at the
    # end of the bash script.
    host_uid = user_id()
    host_gid = group_id()

    docker_args =
      ["run", "--rm", "--user", "0:0"] ++
        ["-v", "#{volume}:#{build_path}"] ++
        Enum.flat_map(bind_mount_paths, fn p -> ["-v", "#{p}:#{p}"] end) ++
        env_args(env) ++
        ["-e", "HOST_UID=#{host_uid}", "-e", "HOST_GID=#{host_gid}"] ++
        [@image, "bash", "-c", bash_script]

    Mix.shell().info("[nbpr] running BR build in docker (volume #{volume})")

    case System.cmd("docker", docker_args,
           stderr_to_stdout: true,
           into: IO.stream(:stdio, :line)
         ) do
      {_, 0} ->
        Path.join(extract_dir, "per-package")

      {_, status} ->
        raise "Buildroot build (in docker) failed with exit status #{status}"
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

  defp build_script(build_path, defconfig_host, br_source, br_package, extract_dir) do
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
      local src_root="$1" dst_root="$2" list="$3"
      [ -f "$list" ] || return 0

      # files-list format: `<pkg>,./<path>` (one per line). Strip the
      # `<pkg>,` prefix to get the relative path.
      while IFS= read -r line; do
        path="${line#*,}"
        case "$path" in
          # Drop dev/docs paths — runtime-only artefact.
          ./usr/include/*|./usr/lib/pkgconfig/*) continue ;;
          ./usr/share/doc/*|./usr/share/man/*|./usr/share/info/*) continue ;;
          *.la) continue ;;
          *) ;;
        esac

        rel="${path#./}"
        src_path="$src_root/$rel"
        dst_path="$dst_root/$rel"
        [ -e "$src_path" ] || [ -L "$src_path" ] || continue

        mkdir -p "$(dirname "$dst_path")"
        cp -aP "$src_path" "$dst_path"
      done < "$list"
    }

    copy_listed "#{pp_src}/target" "#{pp_dst}/target" "$BUILD_DIR/.files-list.txt"
    copy_listed "#{pp_src}/staging" "#{pp_dst}/staging" "$BUILD_DIR/.files-list-staging.txt"

    # Drop empty staging dir so Harvest's existence check skips it cleanly.
    if [ -z "$(ls -A "#{pp_dst}/staging" 2>/dev/null)" ]; then
      rmdir "#{pp_dst}/staging"
    fi

    # Concatenate upstream licence files into a single `legal-info/<pkg>.txt`,
    # matching the canonical artefact layout. Empty / missing licences-dir is
    # not fatal (some packages don't declare `FOO_LICENSE_FILES`).
    LICENSE_DIR=$(ls -d #{shell_quote(build_path)}/legal-info/licenses/#{br_package}-*/ 2>/dev/null | head -1)
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

    # Make the extracted output owned by the host user so the Mix task
    # (running as that user) can read it. The volume itself stays root-owned
    # — that's fine, we never read it directly from the host.
    chown -R "${HOST_UID}:${HOST_GID}" #{shell_quote(extract_dir)}
    """
  end

  defp shell_quote(s) do
    # Single-quote with embedded quote escaping for paths in bash scripts.
    "'" <> String.replace(s, "'", "'\\''") <> "'"
  end

  defp ensure_available! do
    unless available?() do
      raise """
      `docker` not found on PATH. `mix nbpr.build` falls back to Docker when
      not running inside `mix nerves.system.shell`. Either:

        - install Docker, or
        - run `mix nbpr.build` from inside `mix nerves.system.shell`, or
        - set `IN_NERVES_DEV_SHELL=1` if you're confident the host env matches
          the canonical Nerves build container
      """
    end
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
