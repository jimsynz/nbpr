defmodule Mix.Tasks.Nbpr.New do
  @shortdoc "Scaffold a new NBPR package"

  @moduledoc """
  Scaffolds a new NBPR package under `./packages/nbpr_<name>/`.

      mix nbpr.new <name> [options]

  `<name>` must be lowercase, start with a letter, and contain only
  `[a-z0-9_]` (e.g. `jq`, `dnsmasq`, `containerd`).

  By default the generator looks the package up in the Buildroot tree
  pinned by the workspace's `nerves_system_br` dep and pre-fills the
  scaffolded `mix.exs` and module with the upstream version, SPDX
  licences, homepage, and a starter description. Run `mix deps.get` for a
  target first so `deps/nerves_system_br/` exists; on the first run the
  BR tarball (~50 MB) is cached under `$NERVES_ARTIFACTS_DIR/nbpr/`
  (defaulting to `~/.local/share/nerves/nbpr/`).

  ## Options

    * `--no-lookup` — skip BR metadata lookup; emit a stub the user fills
      in. Use for vendored packages (`br_external_path:`) or air-gapped
      workflows.
    * `--br-package <name>` — Buildroot package name when it differs from
      the Hex package name. The Hex name `<name>` becomes `nbpr_<name>`
      regardless.
    * `--licenses "<id>[,<id>...]"` — override the SPDX licences. Required
      when BR's `<NAME>_LICENSE` strings aren't valid SPDX identifiers
      (e.g. `GPL-2.0+`); the generator prints similarity-ranked
      suggestions to choose from.

  ## What gets generated

  The generator owns the package-name → module-name mapping (`nbpr_foo` →
  `NBPR.Foo`). It writes a `mix.exs` with full Hex metadata, a
  `lib/nbpr/<name>.ex` containing the `NBPR.BrPackage` `use` block, a
  README, and a smoke test.
  """

  use Mix.Task

  alias NBPR.Buildroot
  alias NBPR.Buildroot.Package, as: BrPackage
  alias NBPR.Buildroot.Source
  alias NBPR.Spdx

  @switches [no_lookup: :boolean, br_package: :string, licenses: :string]

  @impl Mix.Task
  def run(args) do
    {opts, args} = OptionParser.parse!(args, strict: @switches)

    case args do
      [name] -> generate(name, opts)
      _ -> Mix.raise("usage: mix nbpr.new <name> [--no-lookup] [--br-package X] [--licenses ...]")
    end
  end

  defp generate(name, opts) do
    validate_name!(name)

    package = "nbpr_#{name}"
    workspace = find_workspace_root!()
    target_dir = Path.join([workspace, "packages", package])

    if File.exists?(target_dir) do
      Mix.raise(
        "#{Path.relative_to_cwd(target_dir)} already exists; pick a different name or remove it first"
      )
    end

    module = "NBPR.#{Macro.camelize(name)}"
    project_module = "Nbpr.#{Macro.camelize(name)}.MixProject"
    br_package_name = opts[:br_package] || name
    github_repo = derive_github_repo(workspace)

    metadata = lookup_metadata(name, br_package_name, opts, workspace)
    {resolved_deps, missing_deps} = resolve_sibling_deps(metadata, workspace)

    files =
      build_files(
        name,
        package,
        module,
        project_module,
        br_package_name,
        metadata,
        github_repo,
        resolved_deps
      )

    write_files!(target_dir, files)
    warn_missing_deps(missing_deps)
    print_next_steps(target_dir, module, metadata)
  end

  # Splits BR target dependencies into:
  #   * resolved — `{:nbpr_<dep>, "~> x.y"}` siblings already scaffolded
  #     under `packages/`, ready to wire up via `nbpr_dep/2`.
  #   * missing  — BR dep names with no corresponding `packages/nbpr_<n>/`.
  #     Many will be base-system-provided (e.g. `ncurses`); the generator
  #     can't know, so it warns and lets the author decide.
  defp resolve_sibling_deps(nil, _workspace), do: {[], []}

  defp resolve_sibling_deps(%BrPackage{dependencies: deps}, workspace) do
    packages_dir = Path.join(workspace, "packages")

    Enum.reduce(deps, {[], []}, fn br_dep, {resolved, missing} ->
      nbpr_name = "nbpr_" <> normalise_dep_name(br_dep)
      sibling_dir = Path.join(packages_dir, nbpr_name)

      case sibling_version(sibling_dir) do
        {:ok, version} ->
          {[{nbpr_name, hex_requirement(version)} | resolved], missing}

        :error ->
          {resolved, [br_dep | missing]}
      end
    end)
    |> then(fn {resolved, missing} -> {Enum.reverse(resolved), Enum.reverse(missing)} end)
  end

  # BR uses hyphens in some package directory names (e.g. `kernel-modules`),
  # but nbpr workspace package names are `[a-z0-9_]` only. Map `-` → `_`.
  defp normalise_dep_name(name), do: String.replace(name, "-", "_")

  defp sibling_version(sibling_dir) do
    mix_path = Path.join(sibling_dir, "mix.exs")

    with true <- File.exists?(mix_path),
         {:ok, contents} <- File.read(mix_path),
         [_, version] <- Regex.run(~r/@version\s+"([^"]+)"/, contents) do
      {:ok, version}
    else
      _ -> :error
    end
  end

  defp warn_missing_deps([]), do: :ok

  defp warn_missing_deps(missing) do
    list = Enum.map_join(missing, "\n", &"  - #{&1}")

    Mix.shell().info("""

    Warning: this package's Buildroot metadata declares target dependencies
    that aren't packaged in this workspace yet:

    #{list}

    Some may be provided by the base Nerves system (e.g. `ncurses`,
    `openssl`); others will need their own NBPR package before this one
    will build. For each missing dep that the base system doesn't ship:

        mix nbpr.new <dep>

    Then add `nbpr_dep(:nbpr_<dep>, "~> x.y")` to this package's deps/0.
    """)
  end

  defp lookup_metadata(name, br_package_name, opts, workspace) do
    if opts[:no_lookup], do: nil, else: do_lookup!(name, br_package_name, opts, workspace)
  end

  defp do_lookup!(name, br_package_name, opts, workspace) do
    nerves_br = locate_nerves_system_br!(workspace)
    {:ok, version} = Buildroot.br_version(nerves_br)
    patches = Buildroot.patches_path(nerves_br) |> ok_value()

    ensure_br_tree_with_prompt!(version)
    br_tree = Source.ensure!(version, patches)

    case BrPackage.read(br_tree, br_package_name) do
      {:ok, pkg} ->
        licences = resolve_licences!(pkg.licences, opts[:licenses])
        Map.put(pkg, :licences, licences)

      {:error, :package_not_found} ->
        Mix.raise("""
        no Buildroot package named #{inspect(br_package_name)} in BR #{version}.

        - If the BR name differs from the Hex name #{inspect(name)}, pass
          `--br-package <br-name>`.
        - For a vendored (out-of-tree) package, pass `--no-lookup` and
          declare `br_external_path:` instead of `br_package:`.
        """)

      {:error, reason} ->
        Mix.raise("BR metadata read for #{inspect(br_package_name)} failed: #{inspect(reason)}")
    end
  end

  defp locate_nerves_system_br!(workspace) do
    deps_path = Path.join(workspace, "deps")

    case Buildroot.nerves_system_br_path(deps_path) do
      {:ok, path} ->
        path

      {:error, :not_found} ->
        Mix.raise("""
        `deps/nerves_system_br/` not found in this workspace.

        The generator reads the pinned Buildroot version from
        `nerves_system_br/scripts/create-build.sh`. Fetch deps for a
        target first:

            MIX_TARGET=rpi4 mix deps.get

        Or pass `--no-lookup` to skip BR introspection entirely.
        """)
    end
  end

  defp ensure_br_tree_with_prompt!(version) do
    cond do
      Source.cached?(version) ->
        :ok

      Source.tarball_cached?(version) ->
        :ok

      true ->
        prompt_and_continue!(version)
    end
  end

  defp prompt_and_continue!(version) do
    tarball = Source.tarball_path(version)

    message =
      "About to download buildroot-#{version}.tar.gz (~50 MB) to " <>
        "#{Path.dirname(tarball)}.\n" <>
        "It will be reused on subsequent `mix nbpr.new` runs.\nContinue?"

    if Mix.shell().yes?(message) do
      :ok
    else
      Mix.raise(
        "aborted: BR tarball needed for metadata lookup. Re-run with `--no-lookup` to skip."
      )
    end
  end

  defp resolve_licences!(_br_licences, override) when is_binary(override) do
    override
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> tap(fn list ->
      if list == [], do: Mix.raise("--licenses must list at least one SPDX identifier")
    end)
  end

  defp resolve_licences!(br_licences, nil) do
    results =
      Enum.map(br_licences, fn id ->
        case Spdx.validate(id) do
          :ok -> {:ok, id}
          {:error, suggestions} -> {:error, id, suggestions}
        end
      end)

    case Enum.filter(results, &match?({:error, _, _}, &1)) do
      [] ->
        Enum.map(results, fn {:ok, id} -> id end)

      errors ->
        details =
          errors
          |> Enum.map(fn {:error, id, suggestions} ->
            "  - #{id}: did you mean #{Enum.join(suggestions, ", ")}?"
          end)
          |> Enum.join("\n")

        Mix.raise("""
        Buildroot licence(s) not in SPDX:
        #{details}

        Re-run with `--licenses "<id>[,<id>...]"` to override.
        """)
    end
  end

  defp validate_name!(name) do
    unless Regex.match?(~r/^[a-z][a-z0-9_]*$/, name) do
      Mix.raise(
        "invalid package name: #{inspect(name)}. " <>
          "Must be lowercase, start with a letter, and contain only [a-z0-9_]."
      )
    end

    if String.starts_with?(name, "nbpr_") do
      stripped = String.replace_prefix(name, "nbpr_", "")

      Mix.raise(
        "package name #{inspect(name)} already starts with `nbpr_`; " <>
          "drop the prefix and use #{inspect(stripped)} instead. " <>
          "The generator adds the `nbpr_` prefix automatically."
      )
    end
  end

  defp find_workspace_root! do
    case do_find_workspace_root(File.cwd!()) do
      nil ->
        Mix.raise("""
        Could not locate nbpr workspace root from current directory.

        The workspace root is the directory containing both `PLAN.md` and a
        `nbpr/` subdirectory (the library). Run `mix nbpr.new` from anywhere
        inside the nbpr workspace tree.
        """)

      path ->
        path
    end
  end

  defp do_find_workspace_root(path) do
    cond do
      workspace_root?(path) -> path
      path == "/" -> nil
      true -> do_find_workspace_root(Path.dirname(path))
    end
  end

  defp workspace_root?(path) do
    File.exists?(Path.join(path, "PLAN.md")) and
      File.dir?(Path.join(path, "nbpr"))
  end

  defp build_files(
         short,
         package,
         module,
         project_module,
         br_package_name,
         metadata,
         github_repo,
         resolved_deps
       ) do
    %{
      ".formatter.exs" => formatter_exs(),
      ".gitignore" => gitignore(),
      "README.md" => readme_md(short, package, br_package_name, metadata, github_repo),
      "mix.exs" =>
        mix_exs(package, project_module, br_package_name, metadata, github_repo, resolved_deps),
      "lib/nbpr/#{short}.ex" => package_module_ex(module, br_package_name, metadata, github_repo),
      "test/test_helper.exs" => "ExUnit.start()\n",
      "test/nbpr/#{short}_test.exs" => test_ex(module, br_package_name, metadata, github_repo)
    }
  end

  defp write_files!(target_dir, files) do
    Enum.each(files, fn {relative_path, contents} ->
      full_path = Path.join(target_dir, relative_path)
      full_path |> Path.dirname() |> File.mkdir_p!()
      File.write!(full_path, contents)
      Mix.shell().info("* creating #{full_path}")
    end)
  end

  defp print_next_steps(target_dir, module, metadata) do
    short = target_dir |> Path.basename() |> String.replace_prefix("nbpr_", "")
    relative = Path.relative_to_cwd(target_dir)

    metadata_summary =
      case metadata do
        nil ->
          "Stubbed (no BR lookup). Edit lib/nbpr/#{short}.ex to fill in the package metadata."

        %BrPackage{} = pkg ->
          "Pre-filled from Buildroot: version #{pkg.version}, " <>
            "licences #{Enum.join(pkg.licences, ", ")}. " <>
            "Review lib/nbpr/#{short}.ex and tighten the description if needed."
      end

    Mix.shell().info("""

    Scaffolded #{relative} (#{module}).

    #{metadata_summary}

    Next steps:

        cd #{relative}
        mix deps.get
        mix test
    """)
  end

  defp formatter_exs do
    """
    [
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    """
  end

  defp gitignore do
    """
    _build/
    deps/
    *.beam
    erl_crash.dump
    .elixir_ls/
    """
  end

  defp readme_md(_short, package, br_package_name, metadata, github_repo) do
    {tagline, upstream_line, hex_requirement} =
      readme_fragments(br_package_name, metadata, package)

    """
    # #{package}
    #{tagline}#{upstream_line}

    ## Usage

    In your Nerves project's `mix.exs`:

        {:#{package}, "#{hex_requirement}", organization: "nbpr"}

    Run `mix deps.get`, then `mix firmware` — the binary lands at
    `<release>/lib/#{package}-<vsn>/priv/usr/...` and `NBPR.Application`
    adds it to `PATH` and `LD_LIBRARY_PATH` at boot. See the
    [NBPR README](https://github.com/#{github_repo}) for the full
    integration flow (including supervision-tree wiring for
    daemon-bearing packages).

    ## Configuration

    Build options can be overridden in your app's `config/target.exs`:

        config :#{package}, build_opts: [
          # ...
        ]
    """
  end

  defp readme_fragments(br_package_name, nil, _package) do
    {"\n`#{br_package_name}` packaged for Nerves.\n", "", "~> 0.1"}
  end

  defp readme_fragments(br_package_name, %BrPackage{} = pkg, _package) do
    upstream =
      case pkg.homepage do
        nil -> "`#{br_package_name}`"
        url -> "[`#{br_package_name}`](#{url})"
      end

    description = pkg.description || "Buildroot package `#{br_package_name}`"

    tagline =
      "\n> #{description}\n\n#{upstream} packaged for Nerves. Tracks the upstream Buildroot `#{br_package_name}` package — this release wraps **#{pkg.version}**.\n"

    {tagline, "", hex_requirement(pkg.version)}
  end

  # Hex `~> X.Y` matches `>= X.Y, < X+1.0`, so we advertise the major
  # series the published version belongs to. For `0.x` we widen to
  # `~> 0.1` since pre-1.0 has weaker compatibility guarantees.
  defp hex_requirement(version) do
    case String.split(version, ".") do
      ["0", _ | _] -> "~> 0.1"
      [major, _ | _] -> "~> #{major}.0"
      _ -> "~> 0.1"
    end
  end

  defp mix_exs(package, project_module, br_package_name, metadata, github_repo, resolved_deps) do
    {version, description, links_block, licences} =
      mix_metadata_fragments(br_package_name, metadata, github_repo)

    """
    defmodule #{project_module} do
      use Mix.Project

      @version "#{version}"

      def project do
        [
          app: :#{package},
          version: @version,
          elixir: "~> 1.16",
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          description: #{inspect(description)},
          package: [
            organization: "nbpr",
            licenses: #{inspect(licences)},
            links: #{links_block}
          ]
        ]
      end

      def application do
        [extra_applications: [:logger]]
      end

      defp deps do
        [
          #{deps_list_body(resolved_deps)}
        ]
      end

      # Path dep for local dev (sibling in the workspace); Hex requirement
      # when publishing. Hex publish forbids path deps, so we switch the
      # spec only when the workflow asks for it. `:nbpr` itself lives on
      # public hex.pm; `:nbpr_*` packages live in the `nbpr` Hex org.
      defp nbpr_dep(:nbpr = name, requirement) do
        case System.get_env("NBPR_RELEASE") do
          "1" -> {name, requirement}
          _ -> {name, path: nbpr_dep_path(name)}
        end
      end

      defp nbpr_dep(name, requirement) do
        case System.get_env("NBPR_RELEASE") do
          "1" -> {name, requirement, organization: "nbpr"}
          _ -> {name, path: nbpr_dep_path(name)}
        end
      end

      defp nbpr_dep_path(:nbpr), do: "../../nbpr"
      defp nbpr_dep_path(name) when is_atom(name), do: "../" <> Atom.to_string(name)
    end
    """
  end

  defp deps_list_body(resolved_deps) do
    base = [~s|nbpr_dep(:nbpr, "~> 0.2")|]

    sibling_lines =
      Enum.map(resolved_deps, fn {nbpr_name, requirement} ->
        ~s|nbpr_dep(:#{nbpr_name}, "#{requirement}")|
      end)

    Enum.join(base ++ sibling_lines, ",\n      ")
  end

  defp mix_metadata_fragments(br_package_name, nil, github_repo) do
    links = %{
      br_package_name => "https://example.com/#{br_package_name}",
      "GitHub" => "https://github.com/#{github_repo}"
    }

    {"0.1.0", "TODO: short description for nbpr_#{br_package_name}", inspect(links),
     ["TODO-LICENSE"]}
  end

  defp mix_metadata_fragments(br_package_name, %BrPackage{} = pkg, github_repo) do
    homepage = pkg.homepage || "https://github.com/#{github_repo}"

    links = %{br_package_name => homepage, "GitHub" => "https://github.com/#{github_repo}"}

    description = pkg.description || "TODO: short description for nbpr_#{br_package_name}"
    {pad_version(pkg.version), description, inspect(links), pkg.licences}
  end

  # Buildroot versions like `2.91` aren't valid Hex semver; pad with `.0`.
  # Already-3-component versions pass through.
  defp pad_version(version) do
    case String.split(version, ".") do
      [_, _] -> version <> ".0"
      [_] -> version <> ".0.0"
      _ -> version
    end
  end

  defp package_module_ex(module, br_package_name, nil, github_repo) do
    """
    defmodule #{module} do
      @moduledoc \"\"\"
      NBPR package for `#{br_package_name}`.

      See https://github.com/#{github_repo} for usage.
      \"\"\"

      use NBPR.BrPackage,
        version: 1,
        br_package: #{inspect(br_package_name)},
        description: "TODO: short description for nbpr_#{br_package_name}",
        artifact_sites: [{:ghcr, "ghcr.io/#{github_repo}"}]
    end
    """
  end

  defp package_module_ex(module, br_package_name, %BrPackage{} = pkg, github_repo) do
    homepage_line =
      if pkg.homepage, do: "    homepage: #{inspect(pkg.homepage)},\n", else: ""

    moduledoc = build_moduledoc(br_package_name, pkg)

    """
    defmodule #{module} do
      @moduledoc \"\"\"
    #{moduledoc}
      \"\"\"

      use NBPR.BrPackage,
        version: 1,
        br_package: #{inspect(br_package_name)},
        description: #{inspect(pkg.description)},
    #{homepage_line}    artifact_sites: [{:ghcr, "ghcr.io/#{github_repo}"}]
    end
    """
  end

  defp build_moduledoc(br_package_name, %BrPackage{} = pkg) do
    link =
      case pkg.homepage do
        nil -> "`#{br_package_name}`"
        url -> "[`#{br_package_name}`](#{url})"
      end

    body =
      case pkg.help do
        nil ->
          pkg.description || "TODO: describe #{br_package_name}"

        help ->
          help
          |> first_paragraph()
          |> String.replace(~r/\n/, " ")
          |> String.trim()
      end

    "  NBPR package for #{link} — #{decapitalise_first(body)}"
  end

  defp first_paragraph(text) do
    text
    |> String.split(~r/\n\s*\n/, trim: true)
    |> List.first()
    |> Kernel.||("")
  end

  defp decapitalise_first(""), do: ""

  defp decapitalise_first(<<first::utf8, rest::binary>>) do
    <<String.downcase(<<first::utf8>>)::binary, rest::binary>>
  end

  defp test_ex(module, br_package_name, metadata, github_repo) do
    {description_line, homepage_line, artifact_sites_value} =
      case metadata do
        %BrPackage{description: desc, homepage: home} ->
          {"    assert pkg.description == #{inspect(desc)}\n",
           if(home, do: "    assert pkg.homepage == #{inspect(home)}\n", else: ""),
           [{:ghcr, "ghcr.io/#{github_repo}"}]}

        nil ->
          {"", "", [{:ghcr, "ghcr.io/#{github_repo}"}]}
      end

    name_atom = atom_for_module(module)

    """
    defmodule #{module}Test do
      use ExUnit.Case, async: true

      test "package metadata is well-formed" do
        pkg = #{module}.__nbpr_package__()

        assert pkg.module == #{module}
        assert pkg.name == #{inspect(name_atom)}
        assert pkg.version == 1
        assert pkg.br_package == #{inspect(br_package_name)}
    #{description_line}#{homepage_line}    assert pkg.artifact_sites == #{inspect(artifact_sites_value)}
        assert pkg.daemons == []
        assert pkg.kernel_modules == []
      end
    end
    """
  end

  defp atom_for_module(module) do
    module
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp ok_value({:ok, v}), do: v
  defp ok_value(_), do: nil

  # Derives `<owner>/<repo>` from the workspace's git origin remote so the
  # generated package's links and `artifact_sites:` point at whichever fork
  # this generator was run from. Falls back to `OWNER/REPO` if the workspace
  # isn't a git checkout or the remote URL doesn't parse as github.com.
  defp derive_github_repo(workspace) do
    case System.cmd("git", ["-C", workspace, "remote", "get-url", "origin"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case Regex.run(~r{github\.com[:/]([^/]+)/([^/.\s]+)}, String.trim(output)) do
          [_, owner, repo] -> "#{owner}/#{repo}"
          _ -> "OWNER/REPO"
        end

      _ ->
        "OWNER/REPO"
    end
  end
end
