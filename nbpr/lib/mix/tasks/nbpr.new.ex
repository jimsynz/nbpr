defmodule Mix.Tasks.Nbpr.New do
  @shortdoc "Scaffold a new NBPR package"

  @moduledoc """
  Scaffolds a new NBPR package under `./packages/nbpr_<name>/`.

      mix nbpr.new <name>

  `<name>` must be lowercase, start with a letter, and contain only
  `[a-z0-9_]` (e.g. `jq`, `dnsmasq`, `containerd`).

  Generates a complete Mix project: `mix.exs`, `lib/nbpr/<name>.ex` with the
  `NBPR.BrPackage` macro stubbed in, a smoke test, and a README. The
  generator owns the package-name → module-name mapping (`nbpr_foo` →
  `NBPR.Foo`), so authors don't have to think about camelization.

  Run from the workspace root.
  """

  use Mix.Task

  @impl Mix.Task
  def run([name]) do
    validate_name!(name)

    short = name
    package = "nbpr_#{short}"
    target_dir = Path.join("packages", package)

    if File.exists?(target_dir) do
      Mix.raise("#{target_dir} already exists; pick a different name or remove it first")
    end

    module = "NBPR.#{Macro.camelize(short)}"
    project_module = "Nbpr.#{Macro.camelize(short)}.MixProject"

    files = build_files(short, package, module, project_module)

    write_files!(target_dir, files)
    print_next_steps(target_dir, module)
  end

  def run(_args) do
    Mix.raise("usage: mix nbpr.new <name>")
  end

  defp validate_name!(name) do
    unless Regex.match?(~r/^[a-z][a-z0-9_]*$/, name) do
      Mix.raise(
        "invalid package name: #{inspect(name)}. " <>
          "Must be lowercase, start with a letter, and contain only [a-z0-9_]."
      )
    end
  end

  defp build_files(short, package, module, project_module) do
    %{
      ".formatter.exs" => formatter_exs(),
      ".gitignore" => gitignore(),
      "README.md" => readme_md(short, package, module),
      "mix.exs" => mix_exs(package, project_module),
      "lib/nbpr/#{short}.ex" => package_module_ex(short, module),
      "test/test_helper.exs" => "ExUnit.start()\n",
      "test/nbpr/#{short}_test.exs" => test_ex(module)
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

  defp print_next_steps(target_dir, module) do
    Mix.shell().info("""

    Scaffolded #{target_dir}.

    Next steps:

        cd #{target_dir}
        mix deps.get
        mix test

    Then edit lib/#{Path.relative_to(target_dir <> "/lib", target_dir)}/... to
    flesh out the #{module} package metadata.
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

  defp readme_md(short, package, module) do
    """
    # #{package}

    `#{short}` packaged for Nerves via [NBPR](https://github.com/nerves-project/nbpr).

    ## Usage

    In your Nerves project's `mix.exs`:

        {:#{package}, "~> 0.1", repo: "nbpr"}

    ## Configuration

    Build options can be overridden in your app's `config/target.exs`:

        config :#{package}, build_opts: [
          # ...
        ]

    ## Note for kernel-module packages

    If `#{module}` declares a non-empty `kernel_modules:` list, the using
    project must also include `mod: {#{module}.Application, []}` in its
    `application/0` callback so the Application is started at boot.
    """
  end

  defp mix_exs(package, project_module) do
    """
    defmodule #{project_module} do
      use Mix.Project

      def project do
        [
          app: :#{package},
          version: "0.1.0",
          elixir: "~> 1.16",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      def application do
        [extra_applications: [:logger]]
      end

      defp deps do
        [
          {:nbpr, "~> 0.1"}
        ]
      end
    end
    """
  end

  defp package_module_ex(short, module) do
    """
    defmodule #{module} do
      @moduledoc \"\"\"
      NBPR package for `#{short}`.

      See https://github.com/nerves-project/nbpr for usage.
      \"\"\"

      use NBPR.BrPackage,
        version: 1,
        br_package: "#{short}",
        description: "Replace this with a short description of #{short}"
    end
    """
  end

  defp test_ex(module) do
    """
    defmodule #{module}Test do
      use ExUnit.Case

      test "package metadata is well-formed" do
        pkg = #{module}.__nbpr_package__()
        assert pkg.module == #{module}
        assert pkg.version == 1
      end
    end
    """
  end
end
