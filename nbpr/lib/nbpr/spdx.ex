defmodule NBPR.Spdx do
  @moduledoc """
  SPDX licence-list cache and validation.

  Hex requires `package: [licenses: ...]` entries to be SPDX identifiers.
  Buildroot's `<NAME>_LICENSE` strings are mostly SPDX-aligned but use a
  few non-SPDX forms (`GPL-2.0+` rather than `GPL-2.0-or-later`, etc.) and
  occasionally lag behind the upstream list. The generator validates each
  BR-supplied identifier against the canonical SPDX list and offers
  Jaro-distance suggestions when one doesn't match.

  ## Cache

  The list (~100 KB) is fetched on first use to
  `$NERVES_ARTIFACTS_DIR/nbpr/spdx_licenses.json` (same base as the BR
  tarball cache; `XDG_DATA_HOME`-aware, falling back to `~/.local/share`).
  Subsequent calls read the cached file. Refresh with `refresh!/0` or
  `rm` the file.

  No hardcoded BR-to-SPDX translation table — when BR says `GPL-2.0+`,
  the suggestions surface `GPL-2.0-or-later` and friends, and the user
  picks. This keeps maintenance to zero at the cost of one extra
  decision per non-canonical licence.
  """

  alias NBPR.Artifact.HTTP

  @url "https://spdx.org/licenses/licenses.json"

  @doc """
  Returns the absolute path the SPDX list is (or will be) cached at.
  """
  @spec cache_path() :: Path.t()
  def cache_path do
    Path.join([data_dir(), "nbpr", "spdx_licenses.json"])
  end

  @doc """
  Ensures the SPDX list is cached locally and returns its path. Fetches
  from `#{@url}` on first call.
  """
  @spec ensure_cached!() :: Path.t()
  def ensure_cached! do
    path = cache_path()
    unless File.regular?(path), do: fetch!(path)
    path
  end

  @doc """
  Forces a refresh of the cached SPDX list. Use after an SPDX release if
  validation rejects an identifier you know to be current.
  """
  @spec refresh!() :: Path.t()
  def refresh! do
    path = cache_path()
    _ = File.rm(path)
    fetch!(path)
    path
  end

  @doc """
  Returns the canonical list of *current* SPDX licence IDs — deprecated
  identifiers (`GPL-2.0+`, `GPL-2.0`, etc.) are filtered out so they
  surface as suggestion candidates for their replacements rather than
  passing validation. Hex publish rejects deprecated IDs, so accepting
  them here would just push the failure later.
  """
  @spec license_ids() :: [String.t()]
  def license_ids do
    ensure_cached!()
    |> File.read!()
    |> :json.decode()
    |> Map.fetch!("licenses")
    |> Enum.reject(&Map.get(&1, "isDeprecatedLicenseId", false))
    |> Enum.map(&Map.fetch!(&1, "licenseId"))
  end

  @doc """
  Returns `:ok` when `id` is a valid SPDX licence identifier; otherwise
  `{:error, suggestions}` with up to `n` ranked suggestions (default 3).

  Ranking weights case-insensitive longest-common-prefix heavily, with
  Jaro distance as a tiebreaker. Prefix weighting matters because SPDX
  IDs cluster into families (`GPL-2.0-only`, `GPL-2.0-or-later`, `LGPL-…`)
  and users typing a non-canonical form (`GPL-2.0+`) almost always want a
  sibling within the same family — pure edit-distance metrics rank
  equal-length unrelated IDs (`MPL-2.0`) above the actual family members.
  """
  @spec validate(String.t(), pos_integer()) :: :ok | {:error, [String.t()]}
  def validate(id, n \\ 3) when is_binary(id) and is_integer(n) and n > 0 do
    ids = license_ids()

    if id in ids do
      :ok
    else
      suggestions =
        ids
        |> Enum.map(&{&1, similarity(id, &1)})
        |> Enum.sort_by(fn {_, score} -> -score end)
        |> Enum.take(n)
        |> Enum.map(&elem(&1, 0))

      {:error, suggestions}
    end
  end

  defp similarity(a, b) do
    a_lower = String.downcase(a)
    b_lower = String.downcase(b)

    common_prefix_length(a_lower, b_lower) * 10 + String.jaro_distance(a_lower, b_lower)
  end

  defp common_prefix_length(a, b) do
    do_common_prefix(String.graphemes(a), String.graphemes(b), 0)
  end

  defp do_common_prefix([h | a], [h | b], n), do: do_common_prefix(a, b, n + 1)
  defp do_common_prefix(_, _, n), do: n

  defp fetch!(dest) do
    HTTP.start_apps!()
    File.mkdir_p!(Path.dirname(dest))

    case :httpc.request(
           :get,
           {String.to_charlist(@url), []},
           [autoredirect: true],
           stream: String.to_charlist(dest)
         ) do
      {:ok, :saved_to_file} ->
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        _ = File.rm(dest)
        raise "SPDX list download failed (HTTP #{status}) from #{@url}"

      {:error, reason} ->
        _ = File.rm(dest)
        raise "SPDX list download error: #{inspect(reason)}"
    end
  end

  defp data_dir do
    cond do
      dir = System.get_env("NERVES_ARTIFACTS_DIR") ->
        dir

      true ->
        base = System.get_env("XDG_DATA_HOME") || Path.join(System.user_home!(), ".local/share")
        Path.join(base, "nerves")
    end
  end
end
