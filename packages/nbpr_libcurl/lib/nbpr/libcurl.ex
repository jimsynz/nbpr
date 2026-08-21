defmodule NBPR.Libcurl do
  @moduledoc """
  NBPR package for [`libcurl`](https://curl.se/) — the multi-protocol file
  transfer library behind `curl`.

  Ships `libcurl.so.4` under this package's priv dir; `NBPR.Application`
  prepends it to `LD_LIBRARY_PATH` at boot so sibling packages resolve the
  soname. The staging slice carries the headers, the `.so` symlink,
  `libcurl.pc` and the CMake config, so a NIF can cross-compile against it.

  Packaged because Buildroot's vorbis-tools `select`s libcurl unconditionally
  — `ogg123` plays streams over HTTP — and no Nerves system ships it. Useful
  on its own to anything that wants HTTP from outside the BEAM.

  ## TLS

  Buildroot's TLS-backend choice resolves to OpenSSL here: it's the only
  backend a Nerves system builds, since Erlang's `crypto` needs it. So
  `libcurl.so.4` links the system's own `libssl.so.3` and `libcrypto.so.3`
  and no extra package is needed — but it also means HTTPS from this library
  trusts whatever CA bundle the firmware carries, which for a stock Nerves
  system is none. Ship your own and point at it with `CURLOPT_CAINFO`, or
  `--cacert` from the CLI.

  ## The `curl` binary

  Off by default, as in Buildroot — this is a library package, and the
  prebuilt artefacts carry the library alone. Turn it on for a
  `/usr/bin/curl` in the rootfs, at the cost of a source build (build
  options are part of the artefact cache key, so a non-default value has no
  prebuilt artefact to match):

      config :nbpr_libcurl, build_opts: [curl_binary: true]

  Buildroot builds the library without LDAP, NTLM, curl-debug or the manual
  regardless — none of which is much use on a target with no compiler.

  One oddity comes along either way: curl's `make install` unconditionally
  drops `wcurl`, an 11 kB shell wrapper for downloading files, into
  `usr/bin/`. It shells out to `curl`, so with the option off it's inert.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "libcurl",
    description: "Multi-protocol file transfer library",
    homepage: "https://curl.se/",
    build_opts: [
      curl_binary: [
        type: :boolean,
        default: false,
        br_flag: "BR2_PACKAGE_LIBCURL_CURL",
        doc:
          "Install the `curl` command-line tool alongside the library. Off by default, as in Buildroot — most consumers link the library rather than shell out, and build options are part of the artefact cache key, so turning this on means a source build."
      ]
    ],
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
