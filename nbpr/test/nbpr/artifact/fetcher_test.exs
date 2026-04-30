defmodule NBPR.Artifact.FetcherTest do
  use ExUnit.Case, async: false

  alias NBPR.Artifact.Fetcher

  defmodule WritingResolver do
    @behaviour NBPR.Artifact.Resolver

    @impl true
    def plan({:writing, content}, _inputs) when is_binary(content) do
      {__MODULE__, %{content: content}}
    end

    def plan(_site, _inputs), do: nil

    @impl true
    def get(%{content: content}, dest_path) do
      File.write!(dest_path, content)
      :ok
    end
  end

  defmodule FailingResolver do
    @behaviour NBPR.Artifact.Resolver

    @impl true
    def plan({:failing, reason}, _inputs) do
      {__MODULE__, %{reason: reason}}
    end

    def plan(_site, _inputs), do: nil

    @impl true
    def get(%{reason: reason}, _dest_path), do: {:error, reason}
  end

  @inputs %{
    package_name: "nbpr_jq",
    package_version: "0.1.0",
    system_app: :nerves_system_rpi4,
    system_version: "1.30.0",
    build_opts: []
  }

  setup do
    artifacts_dir =
      Path.join(System.tmp_dir!(), "nbpr_fetcher_test_#{System.unique_integer([:positive])}")

    System.put_env("NERVES_ARTIFACTS_DIR", artifacts_dir)

    on_exit(fn ->
      System.delete_env("NERVES_ARTIFACTS_DIR")
      File.rm_rf!(artifacts_dir)
    end)

    :ok
  end

  describe "fetch!/3" do
    test "writes to the canonical download_path on success" do
      dest =
        Fetcher.fetch!(@inputs, [{:writing, "hello"}], resolvers: [WritingResolver])

      assert dest == NBPR.Artifact.download_path(@inputs)
      assert File.read!(dest) == "hello"
    end

    test "raises with a clear message when no resolver matches the sites" do
      assert_raise RuntimeError, ~r/No resolver could plan/, fn ->
        Fetcher.fetch!(@inputs, [{:unsupported, "foo"}], resolvers: [WritingResolver])
      end
    end

    test "raises when the sites list is empty" do
      assert_raise RuntimeError, ~r/No resolver could plan/, fn ->
        Fetcher.fetch!(@inputs, [], resolvers: [WritingResolver])
      end
    end

    test "tries plans in site declaration order, succeeding on the first" do
      dest =
        Fetcher.fetch!(
          @inputs,
          [{:failing, :first_fails}, {:writing, "second wins"}],
          resolvers: [WritingResolver, FailingResolver]
        )

      assert File.read!(dest) == "second wins"
    end

    test "aggregates errors per resolver when all plans fail" do
      assert_raise RuntimeError,
                   ~r/Failed to fetch.*FailingResolver.*:boom/s,
                   fn ->
                     Fetcher.fetch!(
                       @inputs,
                       [{:failing, :boom}],
                       resolvers: [FailingResolver]
                     )
                   end
    end
  end
end
