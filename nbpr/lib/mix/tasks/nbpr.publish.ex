defmodule Mix.Tasks.Nbpr.Publish do
  @shortdoc "Upload a packed artefact tarball to a GitHub Release"

  @moduledoc """
  Uploads a tarball produced by `mix nbpr.pack` to a GitHub Release on the
  repository declared by the package's `artifact_sites:`.

      mix nbpr.publish <Module> <path-to-tarball>

  e.g.

      mix nbpr.publish NBPR.Jq /path/to/nbpr_jq-1.7.1-...-cb13a42462c2806d.tar.gz

  ## What it does

  1. Reads `__nbpr_package__/0` on the supplied module to get the
     `artifact_sites` (only `{:github_releases, "owner/repo"}` is supported)
     and infer the release tag — `<package>-v<package-version>`, where
     `<package-version>` is the running app's version (`Application.spec/2`).
  2. Creates the release if it doesn't exist (`gh release create`), or
     uploads the asset to the existing release (`gh release upload`).
  3. Replaces an existing asset of the same name (`--clobber`).

  ## Requirements

  The `gh` CLI must be on PATH and authenticated (`gh auth status`). Token
  scope must allow writes to the target repository.

  ## Flags

    * `--draft` — create the release as a draft (only applies on first creation)
    * `--prerelease` — mark the release as a prerelease (first creation only)
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
    repo = github_repo!(pkg)
    tag = release_tag!(pkg)

    ensure_gh!()
    ensure_release!(repo, tag, opts)
    upload_asset!(repo, tag, tarball)

    Mix.shell().info("[nbpr] uploaded #{Path.basename(tarball)} to #{repo}@#{tag}")
  end

  defp parse_positional!([module, tarball]), do: {module, tarball}
  defp parse_positional!(_), do: Mix.raise("usage: mix nbpr.publish <Module> <tarball>")

  defp github_repo!(pkg) do
    case Enum.find(pkg.artifact_sites, &match?({:github_releases, _}, &1)) do
      {:github_releases, owner_repo} ->
        owner_repo

      nil ->
        Mix.raise("#{inspect(pkg.module)} has no github_releases artifact_site; cannot publish")
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

  defp ensure_gh! do
    unless System.find_executable("gh") do
      Mix.raise("`gh` CLI not found on PATH; install from https://cli.github.com/")
    end
  end

  defp ensure_release!(repo, tag, opts) do
    case run_gh(["release", "view", tag, "--repo", repo]) do
      {_, 0} ->
        :exists

      {_, _} ->
        flags =
          ["release", "create", tag, "--repo", repo, "--title", tag]
          |> append_if(opts[:draft], "--draft")
          |> append_if(opts[:prerelease], "--prerelease")
          |> Kernel.++([
            "--notes",
            "Automated release for #{tag}."
          ])

        case run_gh(flags) do
          {_, 0} -> :created
          {output, status} -> Mix.raise("gh release create failed (#{status}): #{output}")
        end
    end
  end

  defp upload_asset!(repo, tag, tarball) do
    case run_gh(["release", "upload", tag, tarball, "--repo", repo, "--clobber"]) do
      {_, 0} -> :ok
      {output, status} -> Mix.raise("gh release upload failed (#{status}): #{output}")
    end
  end

  defp run_gh(args) do
    System.cmd("gh", args, stderr_to_stdout: true)
  end

  defp append_if(args, true, flag), do: args ++ [flag]
  defp append_if(args, _, _flag), do: args
end
