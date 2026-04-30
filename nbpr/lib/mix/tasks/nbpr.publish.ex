defmodule Mix.Tasks.Nbpr.Publish do
  @shortdoc "Upload a packed artefact tarball to its declared backend"

  @moduledoc """
  Uploads a tarball produced by `mix nbpr.pack` to the first supported backend
  declared in the package's `artifact_sites:`.

      mix nbpr.publish <Module> <path-to-tarball>

  e.g.

      mix nbpr.publish NBPR.Jq /path/to/nbpr_jq-1.7.1-...-cb13a42462c2806d.tar.gz

  ## Backends

    * `{:ghcr, "ghcr.io/<owner>"}` — pushes a pure-Elixir OCI artefact to
      `ghcr.io/<owner>/<package>:<tag>`. Requires `GHCR_TOKEN` or
      `GITHUB_TOKEN` in the environment (with `write:packages` scope).
    * `{:github_releases, "<owner>/<repo>"}` — uploads via `gh release` to
      tag `<package>-v<package-version>`, creating the release if needed.
      Requires `gh` on PATH and authenticated.

  Sites are tried in `artifact_sites` order; the first site whose backend has
  the required CLI installed is used.

  ## Flags

    * `--draft` — only applies to `github_releases`; creates the release as a draft on first creation.
    * `--prerelease` — only applies to `github_releases`; marks the release as a prerelease on first creation.
  """

  use Mix.Task

  @requirements ["app.config"]

  @switches [draft: :boolean, prerelease: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, switches: @switches)

    {module_name, tarball} = parse_positional!(positional)
    module = Module.concat([module_name])

    unless Code.ensure_loaded?(module) and function_exported?(module, :__nbpr_package__, 0) do
      Mix.raise("#{inspect(module)} is not an NBPR package (no `__nbpr_package__/0`)")
    end

    unless File.regular?(tarball) do
      Mix.raise("tarball not found: #{tarball}")
    end

    pkg = module.__nbpr_package__()

    case pick_site(pkg) do
      {:ghcr, prefix} -> publish_ghcr!(prefix, pkg, tarball)
      {:github_releases, owner_repo} -> publish_release!(owner_repo, pkg, tarball, opts)
      nil -> Mix.raise("no supported `artifact_sites:` declared on #{inspect(module)}")
    end
  end

  defp parse_positional!([module, tarball]), do: {module, tarball}
  defp parse_positional!(_), do: Mix.raise("usage: mix nbpr.publish <Module> <tarball>")

  defp pick_site(pkg) do
    Enum.find(pkg.artifact_sites, fn
      {:ghcr, _} -> true
      {:github_releases, _} -> true
      _ -> false
    end)
  end

  # ───────── GHCR ─────────

  defp publish_ghcr!("ghcr.io/" <> owner = _prefix, pkg, tarball) do
    package_app = "nbpr_#{pkg.name}"
    image = "#{owner}/#{package_app}"
    tag = ghcr_tag!(tarball, package_app)
    reference = "ghcr.io/#{image}:#{tag}"

    NBPR.OCI.Push.push!(image, tag, tarball)
    Mix.shell().info("[nbpr] pushed #{Path.basename(tarball)} to #{reference}")
  end

  defp publish_ghcr!(prefix, _pkg, _tarball) do
    Mix.raise("ghcr prefix must start with `ghcr.io/`; got #{inspect(prefix)}")
  end

  defp ghcr_tag!(tarball_path, package_app) do
    base = Path.basename(tarball_path, ".tar.gz")
    prefix = "#{package_app}-"

    unless String.starts_with?(base, prefix) do
      Mix.raise(
        "tarball filename #{inspect(base)}.tar.gz does not start with #{inspect(prefix)}; " <>
          "is it a canonical `mix nbpr.pack` output?"
      )
    end

    String.replace_prefix(base, prefix, "")
  end

  # ───────── GitHub Releases ─────────

  defp publish_release!(owner_repo, pkg, tarball, opts) do
    unless System.find_executable("gh") do
      Mix.raise("`gh` CLI not found on PATH; install from https://cli.github.com/")
    end

    tag = release_tag!(pkg)

    ensure_release!(owner_repo, tag, opts)

    case run_gh(["release", "upload", tag, tarball, "--repo", owner_repo, "--clobber"]) do
      {_, 0} ->
        Mix.shell().info("[nbpr] uploaded #{Path.basename(tarball)} to #{owner_repo}@#{tag}")

      {output, status} ->
        Mix.raise("gh release upload failed (#{status}): #{output}")
    end
  end

  defp release_tag!(pkg) do
    package_app = String.to_atom("nbpr_#{pkg.name}")

    version =
      case Application.spec(package_app, :vsn) do
        nil -> Mix.raise("could not read version of #{inspect(package_app)}")
        vsn -> to_string(vsn)
      end

    "#{package_app}-v#{version}"
  end

  defp ensure_release!(owner_repo, tag, opts) do
    case run_gh(["release", "view", tag, "--repo", owner_repo]) do
      {_, 0} ->
        :exists

      {_, _} ->
        flags =
          ["release", "create", tag, "--repo", owner_repo, "--title", tag]
          |> append_if(opts[:draft], "--draft")
          |> append_if(opts[:prerelease], "--prerelease")
          |> Kernel.++(["--notes", "Automated release for #{tag}."])

        case run_gh(flags) do
          {_, 0} -> :created
          {output, status} -> Mix.raise("gh release create failed (#{status}): #{output}")
        end
    end
  end

  defp run_gh(args), do: System.cmd("gh", args, stderr_to_stdout: true)

  defp append_if(args, true, flag), do: args ++ [flag]
  defp append_if(args, _, _flag), do: args
end
