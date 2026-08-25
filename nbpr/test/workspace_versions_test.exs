defmodule NBPR.WorkspaceVersionsTest do
  @moduledoc """
  Holds every package in the workspace to `NBPR.Version`'s rules.

  A published package's `mix.exs` can't call into `:nbpr` — Mix evaluates the
  project before any dep exists — so each one carries the coercion inline.
  This is what stops those copies drifting from the library that documents
  them, and what would have caught `nbpr_jpeg_turbo` declaring a version
  hex.pm refuses before the release workflow got there.
  """

  use ExUnit.Case, async: true

  @packages Path.expand("../../packages", __DIR__)
            |> Path.join("nbpr_*/mix.exs")
            |> Path.wildcard()
            |> Enum.sort()

  # The tests below are generated from this list, so an empty one would make
  # the whole module vacuously green.
  if @packages == [] do
    raise "no packages/nbpr_*/mix.exs found — is this a full workspace checkout?"
  end

  describe "every package" do
    for mix_path <- @packages do
      @mix_path mix_path
      @package mix_path |> Path.dirname() |> Path.basename()

      test "#{Path.dirname(mix_path) |> Path.basename()} publishes a version hex.pm accepts" do
        upstream = upstream_version(@mix_path)
        version = NBPR.Version.hex_version(upstream)

        assert NBPR.Version.validate(version) == :ok,
               "#{@package} declares @version #{inspect(upstream)}, which coerces to " <>
                 "#{inspect(version)} — and hex.pm won't take it"
      end

      test "#{Path.dirname(mix_path) |> Path.basename()} carries the current coercion" do
        source = File.read!(@mix_path)

        assert source =~ "version: normalise_version(@version)",
               "#{@package} doesn't route its @version through normalise_version/1"

        assert String.contains?(source, NBPR.Version.normalise_version_source()),
               "#{@package}'s normalise_version/1 has drifted from " <>
                 "NBPR.Version.normalise_version_source/0 — re-copy it verbatim"
      end
    end
  end

  defp upstream_version(mix_path) do
    [_, version] = Regex.run(~r/@version\s+"([^"]+)"/, File.read!(mix_path))
    version
  end
end
