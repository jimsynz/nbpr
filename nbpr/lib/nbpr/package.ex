defmodule NBPR.Package do
  @moduledoc """
  Metadata struct describing an NBPR package.

  Returned by the generated `__nbpr_package__/0` callback on every module that
  does `use NBPR.BrPackage`. The struct is the canonical introspection surface
  for the curated CI, the build runner, and any future tooling.
  """

  alias NBPR.Package.Daemon

  @type artifact_site :: {:github_releases, String.t()} | {:ghcr, String.t()} | {:oci, String.t()}

  @typedoc """
  The C library a Nerves system's toolchain targets. Nerves systems are
  overwhelmingly glibc; `x86_64` is the musl one.
  """
  @type libc :: :gnu | :musl

  @type t :: %__MODULE__{
          name: atom(),
          version: pos_integer(),
          module: module(),
          description: String.t(),
          homepage: String.t() | nil,
          br_package: String.t() | nil,
          br_external_path: String.t() | nil,
          build_opts: keyword(),
          build_opt_extensions: %{atom() => map()},
          daemons: [Daemon.t()],
          kernel_modules: [String.t()],
          runtime_env: [{String.t(), String.t()}],
          unsupported_libc: [libc()],
          artifact_sites: [artifact_site()]
        }

  @doc """
  The Buildroot package name, for a mainline package or a vendored one.

  A mainline package names it, because the name that Buildroot knows and the name
  that Hex knows are not always the same: `bluez-alsa` is `nbpr_bluez_alsa` here,
  and Hex takes no hyphen. **A vendored package is named by its own NBPR name**,
  because the external tree is ours and the two names have no reason to differ.

      iex> NBPR.Package.br_name(%NBPR.Package{name: :bluez_alsa, br_package: "bluez-alsa"})
      "bluez-alsa"

      iex> NBPR.Package.br_name(%NBPR.Package{name: :librespot, br_external_path: "buildroot"})
      "librespot"
  """
  @spec br_name(t()) :: String.t()
  def br_name(%__MODULE__{br_package: br_package}) when is_binary(br_package), do: br_package
  def br_name(%__MODULE__{name: name}), do: to_string(name)

  @doc """
  Whether this package brings its own Buildroot tree.
  """
  @spec vendored?(t()) :: boolean()
  def vendored?(%__MODULE__{br_external_path: path}), do: is_binary(path)

  @doc """
  The absolute path of a vendored package's Buildroot external tree.

  **`br_external_path` is relative to the package's `priv` directory.** A Hex
  package ships `priv`, so the tree travels with the package and it is there at
  build time whether the package came from Hex or from the workspace.

  It returns `nil` for a mainline package.
  """
  @spec external_tree(t()) :: Path.t() | nil
  def external_tree(%__MODULE__{br_external_path: nil}), do: nil

  def external_tree(%__MODULE__{br_external_path: path, name: name}) do
    Path.join(:code.priv_dir(:"nbpr_#{name}"), path)
  end

  defstruct [
    :name,
    :version,
    :module,
    :description,
    :homepage,
    :br_package,
    :br_external_path,
    :build_opts,
    :build_opt_extensions,
    :daemons,
    :kernel_modules,
    :runtime_env,
    :unsupported_libc,
    :artifact_sites
  ]
end
