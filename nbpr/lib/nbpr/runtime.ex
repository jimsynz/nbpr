defmodule NBPR.Runtime do
  @moduledoc """
  Runtime helpers for Application-bearing NBPR packages.

  The generated `NBPR.<Name>.Application` module calls into here to decide
  whether to load kernel modules and how. Keeping these as plain functions
  in a stable module means: the codegen stays trivial, behaviour can be
  changed centrally without rebuilding every package, and tests can target
  the helpers directly.
  """

  @os_release "/etc/os-release"

  @kmod_tools_app :nbpr_kmod

  # Where Buildroot's kmod package puts the tool symlinks varies with the
  # rootfs skeleton (merged-usr or not); the Nerves skeleton is non-merged,
  # which lands them in `sbin/`, but search all four so a skeleton change
  # doesn't break loading.
  @kmod_tool_dirs ["sbin", "usr/sbin", "bin", "usr/bin"]

  @doc """
  Returns `true` when the current process is running on a Nerves target.

  Every Nerves system ships `ID=nerves` in `/etc/os-release`. Used to gate
  kernel-module loading so `mix test` and dev workflows on macOS/Linux are
  unaffected by package Applications.
  """
  @spec on_nerves_target?() :: boolean()
  def on_nerves_target?, do: on_nerves_target?(@os_release)

  @doc false
  @spec on_nerves_target?(Path.t()) :: boolean()
  def on_nerves_target?(os_release_path) do
    case File.read(os_release_path) do
      {:ok, contents} ->
        contents
        |> String.split("\n")
        |> Enum.any?(&(String.trim(&1) in ["ID=nerves", ~s(ID="nerves")]))

      {:error, _} ->
        false
    end
  end

  @doc """
  Loads kernel module `name` for the package `otp_app`, and raises on failure.

  Prefers the package's own priv-shipped `.ko`: stock Nerves systems index
  only the modules the system was built with in `/lib/modules/<ver>/modules.dep`
  (the rootfs is read-only, so `depmod` can't re-index on device), which makes
  an out-of-tree module invisible to `modprobe`-by-name. Instead the `.ko` is
  located under the package's priv dir and loaded by path with `insmod` from
  `:nbpr_kmod`, after `modprobe`-ing its in-tree dependencies (read from the
  module's `depends:` field via `modinfo`).

  Falls back to plain `modprobe <name>` when the package doesn't ship the
  `.ko` itself — i.e. the module is already indexed on the rootfs.

  Idempotent: modules already loaded (per `/sys/module/`) are skipped.
  """
  @spec load_kernel_module!(atom(), String.t()) :: :ok
  def load_kernel_module!(otp_app, name) when is_atom(otp_app) and is_binary(name) do
    cond do
      loaded?(name) -> :ok
      path = find_module(priv_dir(otp_app), name) -> insmod_with_deps!(otp_app, path)
      true -> modprobe!(name)
    end
  end

  @doc """
  Runs `modprobe <name>` and raises on failure.

  modprobe is idempotent (re-loading an already-loaded module is fine) and
  resolves its own dependency graph from `modules.dep`, so transitive kernel
  modules don't need to be loaded explicitly. Only works for modules the
  system's `modules.dep` indexes — for a package-shipped out-of-tree `.ko`,
  see `load_kernel_module!/2`.
  """
  @spec modprobe!(String.t()) :: :ok
  def modprobe!(name) when is_binary(name) do
    unless System.find_executable("modprobe") do
      raise "modprobe #{name} failed: modprobe binary not found on PATH"
    end

    case System.cmd("modprobe", [name], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, code} ->
        raise "modprobe #{name} failed (exit #{code}): #{String.trim(output)}"
    end
  end

  @doc false
  @spec loaded?(String.t()) :: boolean()
  def loaded?(name) do
    File.dir?(Path.join("/sys/module", normalise_module_name(name)))
  end

  # The kernel treats `-` and `_` as equivalent in module names; filenames
  # and `depends:` entries mix them freely.
  defp normalise_module_name(name), do: String.replace(name, "-", "_")

  @doc false
  @spec find_module(Path.t() | nil, String.t()) :: Path.t() | nil
  def find_module(nil, _name), do: nil

  def find_module(priv, name) do
    stem = normalise_module_name(name)
    pattern = String.replace(stem, "_", "{_,-}")

    priv
    |> Path.join("**/#{pattern}.ko*")
    |> Path.wildcard()
    |> List.first()
  end

  defp insmod_with_deps!(otp_app, path) do
    path
    |> module_depends!()
    |> Enum.each(fn dep ->
      cond do
        loaded?(dep) -> :ok
        dep_path = find_module(priv_dir(otp_app), dep) -> insmod_with_deps!(otp_app, dep_path)
        true -> modprobe!(dep)
      end
    end)

    case run_kmod_tool!("insmod", [path]) do
      {_output, 0} ->
        :ok

      {output, code} ->
        raise "insmod #{path} failed (exit #{code}): #{String.trim(output)}"
    end
  end

  defp module_depends!(path) do
    case run_kmod_tool!("modinfo", ["-F", "depends", path]) do
      {output, 0} ->
        output |> String.trim() |> String.split(",", trim: true)

      {output, code} ->
        raise "modinfo #{path} failed (exit #{code}): #{String.trim(output)}"
    end
  end

  defp run_kmod_tool!(tool, args) do
    priv = kmod_tools_priv!(tool)

    bin =
      Enum.find_value(@kmod_tool_dirs, fn dir ->
        path = Path.join([priv, dir, tool])
        if File.exists?(path), do: path
      end)

    unless bin do
      raise "#{tool} not found under #{inspect(@kmod_tools_app)}'s priv dir; " <>
              "was the package built with the `tools` build option enabled?"
    end

    System.cmd(bin, args, stderr_to_stdout: true, env: [{"LD_LIBRARY_PATH", lib_path(priv)}])
  end

  defp kmod_tools_priv!(tool) do
    priv_dir(@kmod_tools_app) ||
      raise "#{tool} is unavailable: loading a package-shipped kernel module needs " <>
              "the kmod tools, which stock Nerves systems don't include. Add the " <>
              ~s(:nbpr_kmod package \(organization: "nbpr"\) to your deps.)
  end

  defp lib_path(priv) do
    lib_dirs =
      ["usr/lib", "lib"]
      |> Enum.map(&Path.join(priv, &1))
      |> Enum.filter(&File.dir?/1)

    case System.get_env("LD_LIBRARY_PATH") do
      nil -> Enum.join(lib_dirs, ":")
      existing -> Enum.join(lib_dirs ++ [existing], ":")
    end
  end

  defp priv_dir(otp_app) do
    case :code.priv_dir(otp_app) do
      {:error, _} -> nil
      path -> to_string(path)
    end
  end
end
