defmodule NBPR.Elf do
  @moduledoc """
  Minimal ELF introspection: reads a binary's `DT_NEEDED` shared-library
  dependencies via `readelf`.

  Used by `NBPR.Artifact.LibCheck` to find shared libraries an nbpr package's
  binaries link against but that nothing in the firmware provides. Only the
  `NEEDED` list is read — resolution is by soname (filename), matching the
  dynamic loader, so providers don't need their `SONAME` inspected.
  """

  @elf_magic <<0x7F, "ELF">>

  @doc """
  Returns `true` when `readelf` is available on `PATH`.
  """
  @spec available?() :: boolean()
  def available? do
    System.find_executable("readelf") != nil
  end

  @doc """
  Returns `true` when `path` is a regular file whose first bytes are the ELF
  magic number. Cheap pre-filter so `readelf` isn't spawned for scripts,
  configs, and other non-ELF files in a package's `priv/`.
  """
  @spec elf?(Path.t()) :: boolean()
  def elf?(path) do
    File.regular?(path) and
      match?({:ok, @elf_magic}, read_magic(path))
  end

  @doc """
  Returns the `DT_NEEDED` sonames of the ELF at `path`.

  Returns `[]` for a non-dynamic ELF, a non-ELF file, or any `readelf` failure
  — the caller treats "couldn't read deps" the same as "no deps", so a missing
  or odd file never aborts a firmware build.
  """
  @spec needed(Path.t()) :: [String.t()]
  def needed(path) do
    case readelf(path) do
      {:ok, output} -> parse_needed(output)
      :error -> []
    end
  end

  @doc false
  @spec parse_needed(String.t()) :: [String.t()]
  def parse_needed(output) do
    ~r/\(NEEDED\)\s+Shared library:\s+\[([^\]]+)\]/
    |> Regex.scan(output)
    |> Enum.map(fn [_, soname] -> soname end)
  end

  defp readelf(path) do
    case System.cmd("readelf", ["-d", path], stderr_to_stdout: true, env: [{"LC_ALL", "C"}]) do
      {output, 0} -> {:ok, output}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp read_magic(path) do
    File.open(path, [:read, :binary], fn io -> IO.binread(io, 4) end)
  end
end
