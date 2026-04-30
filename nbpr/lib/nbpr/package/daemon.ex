defmodule NBPR.Package.Daemon do
  @moduledoc """
  Metadata struct for a single daemon declared by an NBPR package.

  `argv_template` is an MFA tuple. The function is invoked as
  `module.function(validated_opts, opt_flags, *extra_args)` and must return
  a list of strings (the argv). Defaults to `{NBPR.BrPackage, :default_argv, []}`,
  which performs mechanical `[flag, value]` zipping over the runtime opts.
  Packages with subcommand or positional-argv daemons override with their own
  MFA.
  """

  @type mfa_tuple :: {module(), atom(), [term()]}

  @type t :: %__MODULE__{
          name: atom(),
          module: module(),
          path: String.t(),
          opts: keyword(),
          opt_flags: %{atom() => String.t()},
          argv_template: mfa_tuple()
        }

  defstruct [:name, :module, :path, :opts, :opt_flags, :argv_template]
end
