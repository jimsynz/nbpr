defmodule NBPR.Buildroot.Docker do
  @moduledoc """
  Runs Buildroot `make` invocations inside the canonical Nerves build
  container (`ghcr.io/nerves-project/nerves_system_br:latest`).

  This is the Phase 4.5 fallback for when `mix nbpr.build` is invoked
  outside `mix nerves.system.shell` — the containerised env avoids the
  subtle host-vs-canonical differences in toolchain wrappers, sysroot
  paths, ABI flags etc. that otherwise surface as cryptic `gcc` or
  `ld` errors.

  ## Mount strategy

  Bind-mount each relevant path (BR source, output dir, BR-dl cache, the
  workspace deps providing `NERVES_DEFCONFIG_DIR` and `BR2_EXTERNAL`) at
  the same absolute path inside the container as on the host. That way
  the env vars we pass through are valid in both contexts without any
  translation.

  Files written inside the container land on the host with the host
  user's uid/gid (we pass `--user`), so no chown dance afterwards.
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

  Detection is loose: presence of `/home/nerves/project` (the standard
  working dir in nerves_system_br images) or the `IN_NERVES_DEV_SHELL`
  env var.
  """
  @spec in_canonical_env?() :: boolean()
  def in_canonical_env? do
    System.get_env("IN_NERVES_DEV_SHELL") == "1" or File.dir?("/home/nerves/project")
  end

  @doc """
  Runs `make <args>` in `br_source` inside the container.

  `env` is forwarded as `-e KEY=VAL` flags. Each path referenced (in
  `env` or as `br_source`/`output_dir`/`mounts`) is bind-mounted at
  the same path inside the container.

  `extra_mounts` lets the caller bind paths that aren't otherwise
  reachable from `env` — e.g. workspace `deps/` containing the system
  source.
  """
  @spec run_make!(Path.t(), Path.t(), [{String.t(), String.t()}], [String.t()], [Path.t()]) ::
          :ok
  def run_make!(br_source, output_dir, env, args, extra_mounts \\ []) do
    ensure_available!()

    mount_paths =
      [br_source, output_dir | extra_mounts]
      |> Enum.concat(env_paths(env))
      |> Enum.uniq()
      |> Enum.filter(&File.exists?/1)

    make_args = ["O=#{output_dir}" | args]

    docker_args =
      ["run", "--rm", "--user", "#{user_id()}:#{group_id()}"] ++
        bind_mount_args(mount_paths) ++
        env_args(env) ++
        ["-w", br_source, @image, "make"] ++ make_args

    Mix.shell().info("[nbpr] running in docker: make #{Enum.join(make_args, " ")}")

    case System.cmd("docker", docker_args,
           stderr_to_stdout: true,
           into: IO.stream(:stdio, :line)
         ) do
      {_, 0} ->
        :ok

      {_, status} ->
        raise "Buildroot `make #{Enum.join(args, " ")}` (in docker) failed with exit status #{status}"
    end
  end

  defp ensure_available! do
    unless available?() do
      raise """
      `docker` not found on PATH. `mix nbpr.build` falls back to Docker when
      not running inside `mix nerves.system.shell`. Either:

        - install Docker, or
        - run `mix nbpr.build` from inside `mix nerves.system.shell`, or
        - set IN_NERVES_DEV_SHELL=1 if you're confident the host env matches
          the canonical Nerves build container
      """
    end
  end

  defp bind_mount_args(paths) do
    Enum.flat_map(paths, fn p -> ["-v", "#{p}:#{p}"] end)
  end

  defp env_args(env) do
    Enum.flat_map(env, fn {k, v} -> ["-e", "#{k}=#{v}"] end)
  end

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
