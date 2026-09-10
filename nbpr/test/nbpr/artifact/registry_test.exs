defmodule NBPR.Artifact.RegistryTest do
  use ExUnit.Case, async: false

  alias NBPR.Artifact.Registry
  alias NBPR.Artifact.Resolvers.GHCR

  @inputs %{
    package_name: "nbpr_jq",
    package_version: "1.7.1",
    system_app: :my_custom_system,
    system_version: "1.0.0",
    build_opts: []
  }

  setup do
    for key <- [:registry, :publish_after_build] do
      original = Application.fetch_env(:nbpr, key)
      Application.delete_env(:nbpr, key)

      on_exit(fn ->
        case original do
          {:ok, value} -> Application.put_env(:nbpr, key, value)
          :error -> Application.delete_env(:nbpr, key)
        end
      end)
    end

    :ok
  end

  test "leaves package sites alone without project configuration" do
    sites = [{:ghcr, "ghcr.io/upstream/nbpr"}]
    assert Registry.sites(sites) == sites
  end

  test "searches the project namespace first and deduplicates matching package sites" do
    Application.put_env(:nbpr, :registry, "ghcr.io/my-org/firmware")
    project = {:ghcr, "ghcr.io/my-org/firmware"}
    upstream = {:ghcr, "ghcr.io/upstream/nbpr"}
    assert Registry.sites([upstream, project]) == [project, upstream]
  end

  test "supports a self-hosted Forgejo registry" do
    Application.put_env(:nbpr, :registry, "forgejo.example.com/org/firmware")
    assert Registry.sites([]) == [{:oci, "forgejo.example.com/org/firmware"}]
  end

  test "publishes to Forgejo using the same tag and package as the pull plan" do
    prefix = "forgejo.example.com/org/firmware"
    Application.put_env(:nbpr, :registry, prefix)
    Application.put_env(:nbpr, :publish_after_build, true)
    {_, plan} = NBPR.Artifact.Resolvers.OCI.plan({:oci, prefix}, @inputs)

    Registry.publish_after_build!(@inputs, "built.tar.gz",
      push: fn dest, package, tag, tarball ->
        assert dest == plan.prefix
        assert package == plan.package
        assert tag == plan.tag
        assert tarball == "built.tar.gz"
        send(self(), :forgejo_published)
        :ok
      end
    )

    assert_received :forgejo_published
  end

  test "rejects malformed namespace prefixes" do
    for prefix <- ["ghcr.io/", "ghcr.io/org/", "ghcr.io/org/cache:tag", "ghcr.io/org/cache?query"] do
      Application.put_env(:nbpr, :registry, prefix)
      assert_raise ArgumentError, fn -> Registry.sites([]) end
    end
  end

  test "requires an actual boolean for opt-in publishing" do
    Application.put_env(:nbpr, :publish_after_build, "false")
    assert_raise ArgumentError, ~r/must be a boolean/, fn -> Registry.publish_site!() end
  end

  test "publishing is opt-in even when a registry is configured" do
    Application.put_env(:nbpr, :registry, "ghcr.io/my-org/firmware")
    assert Registry.publish_after_build!(@inputs, "missing.tar.gz") == :ok
  end

  test "publishes to the project namespace with the same tag used for lookup" do
    Application.put_env(:nbpr, :registry, "ghcr.io/my-org/firmware")
    Application.put_env(:nbpr, :publish_after_build, true)
    [{:ghcr, prefix}] = Registry.sites([])
    {GHCR, plan} = GHCR.plan({:ghcr, prefix}, @inputs)

    assert :ok =
             Registry.publish_after_build!(@inputs, "built.tar.gz",
               push: fn image, tag, path ->
                 assert image == plan.image
                 assert tag == plan.tag
                 assert path == "built.tar.gz"
                 send(self(), :published)
                 :ok
               end
             )

    assert_received :published
  end

  test "reports write failures instead of claiming the cache was populated" do
    Application.put_env(:nbpr, :registry, "ghcr.io/my-org/firmware")
    Application.put_env(:nbpr, :publish_after_build, true)

    assert_raise RuntimeError, "push failed", fn ->
      Registry.publish_after_build!(@inputs, "built.tar.gz",
        push: fn _, _, _ -> raise "push failed" end
      )
    end
  end

  test "publishing requires an explicit destination" do
    Application.put_env(:nbpr, :publish_after_build, true)

    assert_raise ArgumentError, ~r/publish_after_build requires/, fn ->
      Registry.publish_after_build!(@inputs, "built.tar.gz")
    end
  end
end
