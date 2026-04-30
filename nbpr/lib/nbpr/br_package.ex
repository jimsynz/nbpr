defmodule NBPR.BrPackage do
  @moduledoc """
  The macro every NBPR package uses.

  ## Daemonless example

      defmodule NBPR.Jq do
        use NBPR.BrPackage,
          version: 1,
          br_package: "jq",
          description: "Lightweight JSON processor",
          homepage: "https://jqlang.github.io/jq/",
          build_opts: [
            oniguruma: [
              type: :boolean,
              default: true,
              br_flag: "BR2_PACKAGE_JQ_ONIGURUMA",
              doc: "Enable Oniguruma regex support"
            ]
          ]
      end

  ## Daemon-bearing example

      defmodule NBPR.Dnsmasq do
        use NBPR.BrPackage,
          version: 1,
          br_package: "dnsmasq",
          description: "Lightweight DHCP/DNS server",
          daemons: [
            dnsmasq: [
              path: "/usr/sbin/dnsmasq",
              opts: [
                config_file: [type: :string, required: true, flag: "--conf-file"],
                keep_in_foreground: [type: :boolean, default: true, flag: "--keep-in-foreground"]
              ]
            ]
          ]
      end

  Each declared daemon emits a nested module (`NBPR.Dnsmasq.Dnsmasq` above) with
  `child_spec/1`, `start_link/1`, and `argv/1`. Users add the daemon module to
  their own supervision tree.

  ## Argv assembly

  The default argv builder zips each runtime opt with its declared `:flag`:
  booleans emit the flag if `true` (nothing if `false`); other values emit
  `[flag, to_string(value)]`. For daemons whose argv has subcommands or
  positional arguments, override with `argv_template:` in the daemon spec —
  any MFA tuple `{module, fun, extra_args}` whose function returns a list of
  strings.
  """

  alias NBPR.Package
  alias NBPR.Package.Daemon

  @current_version 1

  @use_opts_schema NimbleOptions.new!(
                     version: [
                       type: {:in, [@current_version]},
                       required: true,
                       doc: "Schema version. Must be #{@current_version}."
                     ],
                     br_package: [
                       type: :string,
                       doc:
                         "Mainline Buildroot package name. Mutually exclusive with `:br_external_path`."
                     ],
                     br_external_path: [
                       type: :string,
                       doc:
                         "Path to a vendored BR external tree. Mutually exclusive with `:br_package`."
                     ],
                     description: [
                       type: :string,
                       required: true,
                       doc: "Short package description."
                     ],
                     homepage: [type: :string, doc: "Project homepage URL."],
                     build_opts: [
                       type: :keyword_list,
                       default: [],
                       doc:
                         "Build-time options schema (NimbleOptions plus per-option `:br_flag`)."
                     ],
                     daemons: [
                       type: :keyword_list,
                       default: [],
                       doc: "Daemon definitions."
                     ],
                     kernel_modules: [
                       type: {:list, :string},
                       default: [],
                       doc:
                         "Out-of-tree kernel modules. Triggers generation of an Application that runs `modprobe` at boot on Nerves targets."
                     ],
                     artifact_sites: [
                       type: {:list, {:tuple, [{:in, [:github_releases, :ghcr]}, :string]}},
                       default: [],
                       doc:
                         "Where to fetch prebuilt artefact tarballs. Supports `{:ghcr, \"ghcr.io/<owner>\"}` and `{:github_releases, \"<owner>/<repo>\"}`. Sites are tried in order; first one to resolve and download wins."
                     ]
                   )

  @daemon_spec_schema NimbleOptions.new!(
                        path: [
                          type: :string,
                          required: true,
                          doc: "Path to the binary inside the rootfs."
                        ],
                        opts: [
                          type: :keyword_list,
                          default: [],
                          doc: "Runtime opts schema (NimbleOptions plus per-option `:flag`)."
                        ],
                        argv_template: [
                          type: {:tuple, [:atom, :atom, {:list, :any}]},
                          default: {__MODULE__, :default_argv, []},
                          doc: "MFA tuple producing the argv list from validated opts."
                        ]
                      )

  defmacro __using__(opts) do
    {evaluated_opts, _binding} = Code.eval_quoted(opts, [], __CALLER__)
    package = build_metadata!(evaluated_opts, __CALLER__.module)

    daemon_modules = Enum.map(package.daemons, &daemon_module_ast/1)
    application_module = application_module_ast(package, __CALLER__.module)

    quote do
      @nbpr_package unquote(Macro.escape(package))

      @doc """
      Returns the `NBPR.Package` metadata struct for this package.
      """
      @spec __nbpr_package__() :: NBPR.Package.t()
      def __nbpr_package__, do: @nbpr_package

      unquote_splicing(daemon_modules)
      unquote(application_module)
    end
  end

  @doc false
  @spec build_metadata!(keyword(), module()) :: Package.t()
  def build_metadata!(use_opts, caller_module) do
    validated = NimbleOptions.validate!(use_opts, @use_opts_schema)
    validate_br_source!(validated)

    {build_opts_clean, build_opt_extensions} =
      split_extensions(validated[:build_opts], [:br_flag])

    daemons = Enum.map(validated[:daemons], &build_daemon!(&1, caller_module))

    %Package{
      name: derive_name(caller_module),
      version: validated[:version],
      module: caller_module,
      description: validated[:description],
      homepage: validated[:homepage],
      br_package: validated[:br_package],
      br_external_path: validated[:br_external_path],
      build_opts: build_opts_clean,
      build_opt_extensions: build_opt_extensions,
      daemons: daemons,
      kernel_modules: validated[:kernel_modules],
      artifact_sites: validated[:artifact_sites]
    }
  end

  @doc """
  Default argv builder. Zips each opt with its `:flag` extension; booleans emit
  the flag-only form, other values emit `[flag, to_string(value)]`, opts without
  a `:flag` mapping are dropped.
  """
  @spec default_argv(keyword(), %{atom() => String.t()}) :: [String.t()]
  def default_argv(validated_opts, opt_flags) do
    Enum.flat_map(validated_opts, fn {opt_name, value} ->
      case {Map.get(opt_flags, opt_name), value} do
        {nil, _} -> []
        {_, false} -> []
        {flag, true} -> [flag]
        {flag, value} -> [flag, to_string(value)]
      end
    end)
  end

  defp build_daemon!({name, spec}, caller_module) do
    spec = NimbleOptions.validate!(spec, @daemon_spec_schema)
    {opts_clean, ext_map} = split_extensions(spec[:opts], [:flag])
    opt_flags = Enum.into(ext_map, %{}, fn {opt_name, ext} -> {opt_name, Map.get(ext, :flag)} end)

    _validated_schema = NimbleOptions.new!(opts_clean)

    %Daemon{
      name: name,
      module: Module.concat([caller_module, name |> Atom.to_string() |> Macro.camelize()]),
      path: spec[:path],
      opts: opts_clean,
      opt_flags: opt_flags,
      argv_template: spec[:argv_template]
    }
  end

  defp validate_br_source!(validated) do
    case {validated[:br_package], validated[:br_external_path]} do
      {nil, nil} ->
        raise ArgumentError,
              "NBPR.BrPackage: must specify exactly one of :br_package or :br_external_path"

      {pkg, path} when is_binary(pkg) and is_binary(path) ->
        raise ArgumentError,
              "NBPR.BrPackage: :br_package and :br_external_path are mutually exclusive"

      _ ->
        :ok
    end
  end

  defp split_extensions(schema, extension_keys) do
    Enum.map_reduce(schema, %{}, fn {opt_name, opt_spec}, acc ->
      {extracted, remaining} = Keyword.split(opt_spec, extension_keys)
      {{opt_name, remaining}, Map.put(acc, opt_name, Map.new(extracted))}
    end)
  end

  defp derive_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp daemon_module_ast(%Daemon{} = daemon) do
    moduledoc = build_daemon_moduledoc(daemon)

    quote do
      defmodule unquote(daemon.module) do
        @moduledoc unquote(moduledoc)

        @path unquote(daemon.path)
        @runtime_opts_schema unquote(Macro.escape(daemon.opts))
        @opt_flags unquote(Macro.escape(daemon.opt_flags))
        @argv_template unquote(Macro.escape(daemon.argv_template))

        @doc """
        Supervisor child spec — call `start_link/1` with the runtime opts.
        """
        @spec child_spec(keyword()) :: Supervisor.child_spec()
        def child_spec(opts) do
          %{
            id: __MODULE__,
            start: {__MODULE__, :start_link, [opts]}
          }
        end

        @doc """
        Validates `opts`, builds the argv, and starts the daemon under MuonTrap.
        """
        @spec start_link(keyword()) :: GenServer.on_start()
        def start_link(opts) do
          MuonTrap.Daemon.start_link(@path, argv(opts), [])
        end

        @doc """
        Returns the argv list that `start_link/1` would invoke. Validates `opts`
        against the runtime schema. Useful for inspection and testing.
        """
        @spec argv(keyword()) :: [String.t()]
        def argv(opts) do
          validated = NimbleOptions.validate!(opts, @runtime_opts_schema)

          ordered =
            for {opt_name, _spec} <- @runtime_opts_schema, do: {opt_name, validated[opt_name]}

          {mod, fun, extras} = @argv_template
          apply(mod, fun, [ordered, @opt_flags | extras])
        end
      end
    end
  end

  defp application_module_ast(%Package{kernel_modules: []}, _caller_module), do: nil

  defp application_module_ast(%Package{kernel_modules: kmods}, caller_module) do
    app_module = Module.concat([caller_module, "Application"])

    quote do
      defmodule unquote(app_module) do
        @moduledoc """
        Auto-generated Application that loads kernel modules at boot via
        `modprobe`. No-op when not running on a Nerves target, so `mix test`
        and dev workflows are unaffected. `stop/1` is a no-op — kernel modules
        are global resources and never `rmmod`'d.
        """

        use Application

        @kernel_modules unquote(kmods)

        @impl Application
        def start(_type, _args) do
          if NBPR.Runtime.on_nerves_target?() do
            Enum.each(@kernel_modules, &NBPR.Runtime.modprobe!/1)
          end

          Supervisor.start_link([], strategy: :one_for_one, name: __MODULE__)
        end

        @impl Application
        def stop(_state), do: :ok

        @doc """
        Returns the list of kernel modules this Application loads at boot.
        """
        @spec kernel_modules() :: [String.t()]
        def kernel_modules, do: @kernel_modules
      end
    end
  end

  defp build_daemon_moduledoc(%Daemon{} = daemon) do
    """
    Daemon wrapper for `#{daemon.path}`.

    Validates options against the runtime schema, builds argv via
    `#{inspect(elem(daemon.argv_template, 0))}.#{elem(daemon.argv_template, 1)}`,
    and supervises the process under MuonTrap.

    ## Options

    #{NimbleOptions.docs(daemon.opts)}
    """
  end
end
