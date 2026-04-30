defmodule NBPR.Buildroot.SystemSource do
  @moduledoc """
  Resolves a path to the full source tree of an active Nerves system,
  fetching from GitHub when the user has the Hex tarball (which deliberately
  omits `Config.in` and `patches/`).

  ## Why

  Source-build needs the system's full source tree:

    - `Config.in` — referenced by `nerves_system_br/Config.in`
    - `nerves_defconfig` — the system's BR defconfig
    - `patches/buildroot/**` — Nerves' BR patches

  Hex tarballs of `nerves_system_*` exclude `Config.in` and `patches/` because
  Hex consumers use the prebuilt artefact, not source. NBPR users frequently
  only have the Hex dep — we transparently fetch the equivalent source from
  GitHub the first time source-build runs for that (system, version) tuple.

  ## Cache

  Extracted GitHub source lives at:

      <data_dir>/nbpr/system-source/<system_app>-<system_version>/

  with a `.nbpr-ready` marker file once extraction completes successfully.
  Idempotent across runs.
  """

  @doc """
  Returns a path to a full source tree for `system_app` at `system_version`.

  If the user's `deps/<system_app>/` already has `Config.in` (git/path dep,
  or Hex with patches), returns that. Otherwise fetches the GitHub tarball
  for the matching tag, caches it under `<data_dir>/nbpr/system-source/`,
  and returns the cache path.

  Raises if the GitHub URL can't be discovered from `hex_metadata.config`
  or the tarball can't be downloaded.
  """
  @spec ensure!(atom(), String.t()) :: Path.t()
  def ensure!(system_app, system_version)
      when is_atom(system_app) and is_binary(system_version) do
    deps_path = Path.join(Mix.Project.deps_path(), Atom.to_string(system_app))

    cond do
      File.regular?(Path.join(deps_path, "Config.in")) ->
        deps_path

      File.dir?(deps_path) ->
        ensure_from_github!(system_app, system_version, deps_path)

      true ->
        Mix.raise("system source not found at #{deps_path}; ensure `mix deps.get` ran")
    end
  end

  @doc false
  @spec cache_dir(atom(), String.t()) :: Path.t()
  def cache_dir(system_app, system_version) do
    Path.join([data_dir(), "nbpr", "system-source", "#{system_app}-#{system_version}"])
  end

  defp ensure_from_github!(system_app, system_version, deps_path) do
    cache = cache_dir(system_app, system_version)

    if File.regular?(Path.join(cache, ".nbpr-ready")) do
      cache
    else
      github_url = read_github_url!(deps_path, system_app)
      Mix.shell().info("[nbpr] fetching #{system_app} v#{system_version} source from GitHub")
      download_and_extract!(github_url, system_version, cache)
      cache
    end
  end

  defp read_github_url!(deps_path, system_app) do
    metadata_path = Path.join(deps_path, "hex_metadata.config")

    unless File.regular?(metadata_path) do
      Mix.raise("""
      cannot determine GitHub source for #{system_app}: no `hex_metadata.config`
      at #{metadata_path}, and `Config.in` is missing.

      If this is a vendored or non-Hex system, pin it from git in your `mix.exs`:

          {:#{system_app}, github: "<owner>/<repo>", tag: "v<version>", ...}
      """)
    end

    {:ok, terms} = :file.consult(String.to_charlist(metadata_path))

    links =
      Enum.find_value(terms, [], fn
        {<<"links">>, ls} -> ls
        _ -> false
      end)

    case Enum.find(links, fn {k, _} -> k == <<"GitHub">> end) do
      {_, url} ->
        to_string(url)

      nil ->
        Mix.raise("""
        #{system_app}'s `hex_metadata.config` doesn't declare a `links.GitHub`
        entry — can't auto-fetch source for source-build.

        Pin it from git in your `mix.exs`:

            {:#{system_app}, github: "<owner>/<repo>", tag: "v<version>", ...}
        """)
    end
  end

  defp download_and_extract!(github_url, version, cache) do
    {owner, repo} = parse_github_url!(github_url)
    tarball_url = "https://github.com/#{owner}/#{repo}/archive/refs/tags/v#{version}.tar.gz"

    staging = make_tmp_dir!()
    tarball_path = Path.join(staging, "source.tar.gz")

    try do
      download!(tarball_url, tarball_path)
      extract!(tarball_path, staging)

      inner = Path.join(staging, "#{repo}-#{version}")

      unless File.dir?(inner) do
        raise """
        downloaded tarball did not contain expected `#{repo}-#{version}/` directory.
        URL: #{tarball_url}
        """
      end

      File.write!(Path.join(inner, ".nbpr-ready"), version <> "\n")

      File.mkdir_p!(Path.dirname(cache))
      if File.exists?(cache), do: File.rm_rf!(cache)
      File.rename!(inner, cache)
    after
      File.rm_rf!(staging)
    end
  end

  defp parse_github_url!(url) do
    case Regex.run(~r{^https?://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$}, url) do
      [_, owner, repo] -> {owner, repo}
      _ -> Mix.raise("could not parse GitHub URL: #{inspect(url)}")
    end
  end

  defp download!(url, dest_path) do
    :ok = ensure_inets_started()

    case :httpc.request(
           :get,
           {String.to_charlist(url), []},
           [autoredirect: true],
           stream: String.to_charlist(dest_path)
         ) do
      {:ok, :saved_to_file} ->
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        _ = File.rm(dest_path)
        raise "system-source download failed (HTTP #{status}) from #{url}"

      {:error, reason} ->
        _ = File.rm(dest_path)
        raise "system-source download error: #{inspect(reason)}"
    end
  end

  defp extract!(tarball, dest_dir) do
    case System.cmd("tar", ["-xzf", tarball, "-C", dest_dir], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, status} ->
        raise "system-source extract failed (tar exit #{status}): #{String.trim(output)}"
    end
  end

  defp ensure_inets_started do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)
    :ok
  end

  defp make_tmp_dir! do
    dir =
      Path.join(System.tmp_dir!(), "nbpr_system_source_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir
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
end
