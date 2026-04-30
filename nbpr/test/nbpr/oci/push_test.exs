defmodule NBPR.OCI.PushTest do
  use ExUnit.Case, async: true

  alias NBPR.OCI.Push

  describe "build_manifest/5" do
    test "produces a well-formed OCI image manifest with our artifact and layer media types" do
      m =
        Push.build_manifest(
          "sha256:deadbeef",
          1234,
          "nbpr_jq-1.7.1-foo.tar.gz",
          "sha256:cafef00d",
          2
        )

      assert m["schemaVersion"] == 2
      assert m["mediaType"] == "application/vnd.oci.image.manifest.v1+json"
      assert m["artifactType"] == "application/vnd.nbpr.artifact.v1"

      assert m["config"]["mediaType"] == "application/vnd.oci.empty.v1+json"
      assert m["config"]["digest"] == "sha256:cafef00d"
      assert m["config"]["size"] == 2
      assert m["config"]["data"] == Base.encode64("{}")

      [layer] = m["layers"]
      assert layer["mediaType"] == "application/vnd.nbpr.tarball.v1+tar+gzip"
      assert layer["digest"] == "sha256:deadbeef"
      assert layer["size"] == 1234
      assert layer["annotations"]["org.opencontainers.image.title"] == "nbpr_jq-1.7.1-foo.tar.gz"

      assert is_binary(m["annotations"]["org.opencontainers.image.created"])
    end

    test "manifest round-trips through `:json`" do
      m = Push.build_manifest("sha256:a", 1, "x.tar.gz", "sha256:b", 2)
      encoded = m |> :json.encode() |> IO.iodata_to_binary()
      decoded = :json.decode(encoded)

      assert decoded["artifactType"] == "application/vnd.nbpr.artifact.v1"
      assert hd(decoded["layers"])["digest"] == "sha256:a"
    end
  end

  describe "append_digest_param/2" do
    test "uses ? when no query string is present" do
      assert Push.append_digest_param("https://ghcr.io/upload/abc", "sha256:def") ==
               "https://ghcr.io/upload/abc?digest=sha256%3Adef"
    end

    test "uses & when query string already present" do
      assert Push.append_digest_param("https://ghcr.io/upload/abc?_state=xyz", "sha256:def") ==
               "https://ghcr.io/upload/abc?_state=xyz&digest=sha256%3Adef"
    end
  end
end
