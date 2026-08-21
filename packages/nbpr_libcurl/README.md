# nbpr_libcurl

> Multi-protocol file transfer library.

[`libcurl`](https://curl.se/) packaged for Nerves. Tracks the upstream
Buildroot `libcurl` package — this release wraps **8.21.0**.

Licence: curl.


## Usage

Authenticate to the `nbpr` Hex organisation once per machine (the
read key is intentionally public — it gates discoverability of the
org's binary packages, not access to private content):

    mix hex.organization auth nbpr --key 15da04a2330d881e1301a73c5d39f591

Then add this package to your Nerves project's `mix.exs`:

    {:nbpr_libcurl, "~> 8.0", organization: "nbpr"}

Run `mix deps.get`, then `mix firmware`. The full consumer flow —
including the `firmware:` alias that pulls binaries ahead of the
firmware build, and supervision-tree wiring for daemon-bearing
packages — lives in the [NBPR Getting Started
guide](https://hexdocs.pm/nbpr/getting-started.html). The fastest
path to a working setup is `mix igniter.install nbpr`.


## Why it exists

No Nerves system ships libcurl. Checked against the built system artefacts
in the local cache — `rpi0` 2.0.4, `rpi4` 2.1.1, `rpi5` 0.7.0, `bbb`
2.29.5, `trellis` 0.4.2 and `x86_64` 1.30.1 — none has `libcurl.so.4` in
staging.

Buildroot's vorbis-tools `select`s libcurl unconditionally, for `ogg123`'s
HTTP streaming, so [`nbpr_vorbis_tools`](../nbpr_vorbis_tools) depends on
this package. It stands on its own for anything else that wants HTTP from
outside the BEAM.


## TLS and certificates

Buildroot's TLS-backend choice resolves to OpenSSL here — it's the only
backend a Nerves system builds, since Erlang's `crypto` needs it. So
`libcurl.so.4` links the system's own `libssl.so.3` and `libcrypto.so.3`
and no extra package is required.

What the firmware doesn't have is a CA bundle: a stock Nerves rootfs ships
no trust store, so HTTPS verification has nothing to verify against. Ship
your own bundle and point at it (`CURLOPT_CAINFO`, or `--cacert` from the
CLI). Turning verification off instead is not the same thing.


## Configuration

Build options can be overridden in your app's `config/target.exs`:

    config :nbpr_libcurl, build_opts: [curl_binary: true]

`curl_binary` adds `/usr/bin/curl` alongside the library. It's off by
default, matching Buildroot: most consumers want the library, and build
options are part of the artefact cache key — a non-default value has no
prebuilt artefact to match, so it falls to a source build.

Buildroot builds the library without LDAP, NTLM, curl-debug or the manual
regardless. None of that is much use on a target with no compiler.

One oddity arrives either way: curl's `make install` unconditionally drops
`wcurl`, an 11 kB shell wrapper for downloading files, into `usr/bin/`. It
shells out to `curl`, so with the option off it's inert.

Source: <https://github.com/jimsynz/nbpr>.
