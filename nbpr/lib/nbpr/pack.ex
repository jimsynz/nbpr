defmodule NBPR.Pack do
  @moduledoc """
  Produces a canonical NBPR artefact tarball from a directory of built files.

  Given the build inputs (package, version, system, system-version,
  build-opts) plus paths to one or more of `target/`, `staging/`, and
  `legal-info/` source directories, this module assembles them into a
  single top-level directory matching `NBPR.Artifact.dir_name/1`, drops a
  `manifest.json` next to them, and tarballs into a file named per
  `NBPR.Artifact.tarball_name/1`.

  Pure I/O on the local filesystem; no network, no Buildroot. Source-build
  drivers (eventual `mix nbpr.build` and friends) call into this once they
  have a directory of installed files.
  """

  alias NBPR.Artifact

  @type sources :: %{
          optional(:target) => Path.t(),
          optional(:staging) => Path.t(),
          optional(:legal_info) => Path.t()
        }

  @doc """
  Builds the canonical tarball for `inputs`, drawing files from `sources`.

  Returns the absolute path to the produced tarball.
  """
  @spec pack!(Artifact.build_inputs(), sources(), Path.t()) :: Path.t()
  def pack!(%{} = inputs, sources, output_dir) when is_binary(output_dir) do
    File.mkdir_p!(output_dir)

    staging_dir = make_staging_dir!()

    try do
      assemble!(inputs, sources, staging_dir)
      tar_path = Path.join(output_dir, Artifact.tarball_name(inputs))
      tar!(staging_dir, Artifact.dir_name(inputs), tar_path)
      tar_path
    after
      File.rm_rf!(staging_dir)
    end
  end

  defp assemble!(inputs, sources, staging_dir) do
    inner = Path.join(staging_dir, Artifact.dir_name(inputs))
    File.mkdir_p!(inner)

    File.write!(
      Path.join(inner, "manifest.json"),
      [:json.encode(Artifact.manifest(inputs)), ?\n]
    )

    Enum.each([:target, :staging, :legal_info], fn key ->
      copy_source!(sources, key, inner)
    end)
  end

  defp copy_source!(sources, key, inner) do
    case Map.get(sources, key) do
      nil ->
        :ok

      src when is_binary(src) ->
        unless File.dir?(src) do
          raise "source for #{inspect(key)} is not a directory: #{src}"
        end

        dest = Path.join(inner, dest_name(key))
        File.mkdir_p!(dest)
        File.cp_r!(src, dest)
    end
  end

  defp dest_name(:target), do: "target"
  defp dest_name(:staging), do: "staging"
  defp dest_name(:legal_info), do: "legal-info"

  defp tar!(staging_dir, top_level_name, tar_path) do
    File.cd!(staging_dir, fn ->
      :ok =
        :erl_tar.create(
          String.to_charlist(tar_path),
          [String.to_charlist(top_level_name)],
          [:compressed]
        )
    end)
  end

  defp make_staging_dir! do
    dir = Path.join(System.tmp_dir!(), "nbpr_pack_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end
end
