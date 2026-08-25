defmodule NBPR.Version do
  @moduledoc """
  What hex.pm accepts as a version, and how a Buildroot version is coerced
  into one.

  Every `:nbpr_*` package mirrors its Buildroot package's version, and
  Buildroot's versions aren't semver. Three shapes of mismatch turn up:

    * **Too few components** — `dnsmasq` is `2.92`, `kmod` is `34`. Hex
      requires exactly three, so these are padded (`2.92.0`, `34.0.0`).
    * **Too many components** — `libjpeg-turbo` is `3.1.4.1`, a post-release
      fix tagged alongside `3.1.4`.
    * **A patchlevel suffix** — ImageMagick is `7.1.2-26`.

  ## The rules

  A version reaches hex.pm only if it is exactly `MAJOR.MINOR.PATCH`, all
  three numeric with no leading zeros. Two tempting escapes are both closed:

    * **Build metadata** (`3.1.4+1`) is rejected outright — hex.pm answers
      `version: build number not allowed`. It couldn't order anyway:
      `Version.compare("3.1.4+1", "3.1.4")` is `:eq`, since semver ignores
      build metadata when comparing.
    * **A pre-release** (`7.1.2-26`) parses, and hex.pm will accept it, but
      it sorts *below* the release it was meant to supersede
      (`7.1.2-26 < 7.1.2`) and Hex's resolver skips pre-releases unless a
      requirement names one. Consumers on `~> 7.1` would never see it.

  So the fourth component goes. `hex_version/1` drops any trailing numeric
  packaging component — a fourth dot-segment, or a `-N` suffix — and pads
  what's short.

  ## What that costs

  Dropping is lossy, and the loss is real: when upstream moves only the
  component that got dropped (`3.1.4.1` → `3.1.4.2`, `7.1.2-26` →
  `7.1.2-27`), the Hex version doesn't move, so `mix nbpr.releasable` sees
  nothing to release and no new version can be published. Hex has three
  numeric positions and uses all three for ordering; it has no
  packaging-revision field the way Debian (`-N`) or Alpine (`-rN`) do.

  The artefact isn't blocked by this — a tarball is addressed by a cache key
  over the package version, system, system version and build options, so
  rebuilding and re-pushing under the same key needs no Hex release. Only a
  change to a package's *Elixir* source is stuck, and the way out is to
  decouple the Hex version from upstream entirely rather than to find a
  cleverer encoding.

  Anything this module doesn't recognise as numeric — `1.2.3-rc1`, `2.0_p1`
  — passes through untouched, so `validate/1` names the problem instead of
  a coercion silently claiming an upstream release it isn't.
  """

  # Leading zeros are stripped per component (`2.03.31` → `2.3.31`), because
  # semver forbids them and Mix rejects the project outright. The trailing
  # group is the packaging component we drop: `.1` in `3.1.4.1`, `-26` in
  # `7.1.2-26`. Numeric only — a non-numeric suffix is a pre-release and
  # meaningful, so it isn't ours to discard.
  @upstream_version ~r/^0*(?<major>\d+)(?:\.0*(?<minor>\d+))?(?:\.0*(?<patch>\d+))?(?:[.-]\d+)*$/

  @doc """
  Coerces a Buildroot version into the `MAJOR.MINOR.PATCH` shape hex.pm
  requires.

      iex> NBPR.Version.hex_version("1.8.2")
      "1.8.2"

      iex> NBPR.Version.hex_version("2.92")
      "2.92.0"

      iex> NBPR.Version.hex_version("34")
      "34.0.0"

      iex> NBPR.Version.hex_version("3.1.4.1")
      "3.1.4"

      iex> NBPR.Version.hex_version("7.1.2-26")
      "7.1.2"

      iex> NBPR.Version.hex_version("2.03.31")
      "2.3.31"

  A version this can't read is returned as it came, for `validate/1` to
  reject:

      iex> NBPR.Version.hex_version("1.2.3-rc1")
      "1.2.3-rc1"
  """
  @spec hex_version(String.t()) :: String.t()
  def hex_version(upstream) when is_binary(upstream) do
    case Regex.named_captures(@upstream_version, upstream) do
      %{"major" => major, "minor" => minor, "patch" => patch} ->
        "#{major}.#{component(minor)}.#{component(patch)}"

      nil ->
        upstream
    end
  end

  @doc """
  Says whether `version` can be published to hex.pm, and why not when it
  can't.

      iex> NBPR.Version.validate("1.8.2")
      :ok

      iex> NBPR.Version.validate("3.1.4+1")
      {:error, "build metadata is rejected by hex.pm (`version: build number not allowed`)"}

      iex> NBPR.Version.validate("2.92")
      {:error, "not a semantic version — hex.pm needs exactly MAJOR.MINOR.PATCH"}
  """
  @spec validate(String.t()) :: :ok | {:error, String.t()}
  def validate(version) when is_binary(version) do
    case Version.parse(version) do
      {:ok, %Version{build: build}} when is_binary(build) ->
        {:error, "build metadata is rejected by hex.pm (`version: build number not allowed`)"}

      {:ok, %Version{pre: [_ | _]}} ->
        {:error,
         "a pre-release sorts below the release it supersedes, and Hex's " <>
           "resolver won't hand it to a `~>` requirement"}

      {:ok, %Version{}} ->
        :ok

      :error ->
        {:error, "not a semantic version — hex.pm needs exactly MAJOR.MINOR.PATCH"}
    end
  end

  @normalise_version_source """
    # Renovate writes Buildroot's upstream version straight into @version,
    # and Buildroot's versions aren't semver: they can be short (`2.92`),
    # carry a fourth component (`3.1.4.1`) or a patchlevel suffix
    # (`7.1.2-26`). hex.pm takes exactly MAJOR.MINOR.PATCH — it rejects
    # build metadata outright, and a pre-release is invisible to a `~>`
    # requirement — so pad what's short and drop a trailing numeric
    # packaging component. `NBPR.Version` documents the rules and the cost.
    defp normalise_version(version) do
      upstream = ~r/^0*(?<major>\\d+)(?:\\.0*(?<minor>\\d+))?(?:\\.0*(?<patch>\\d+))?(?:[.-]\\d+)*$/

      case Regex.named_captures(upstream, version) do
        %{"major" => major, "minor" => minor, "patch" => patch} ->
          Enum.map_join([major, minor, patch], ".", fn
            "" -> "0"
            segment -> segment
          end)

        nil ->
          version
      end
    end\
  """

  @doc """
  The `normalise_version/1` every package's `mix.exs` carries, as source.

  Mix evaluates a project before its deps exist, so a package can't call
  `hex_version/1` from its own `mix.exs` — it has to carry the coercion
  inline. `mix nbpr.new` writes this text into what it generates, and the
  workspace test asserts every package still contains it, so the copies stay
  mechanical rather than hand-maintained.

  Indented two spaces, ready to splice into a module body.
  """
  @spec normalise_version_source() :: String.t()
  def normalise_version_source, do: @normalise_version_source

  defp component(""), do: "0"
  defp component(segment), do: segment
end
