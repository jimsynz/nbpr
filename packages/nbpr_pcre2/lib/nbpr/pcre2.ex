defmodule NBPR.Pcre2 do
  @moduledoc """
  NBPR package for [`pcre2`](https://www.pcre.org/) — Perl-compatible regular
  expressions.

  Ships `libpcre2-8.so.0` under this package's priv dir; `NBPR.Application`
  prepends it to `LD_LIBRARY_PATH` at boot so sibling packages resolve the
  soname. The staging slice carries `pcre2.h`, the `.so` symlink,
  `libpcre2-8.pc` and `pcre2-config`, so a NIF can cross-compile against it.

  Packaged because `:nbpr_libglib2` needs it — GLib's `GRegex` is a wrapper
  over PCRE2 — and no Nerves system ships it. The BEAM has `:re` (which links
  its own vendored PCRE), so Elixir code has no reason to reach for this
  directly.

  Upstream's `pcre2grep` and `pcre2test` are installed alongside the library
  and Buildroot doesn't remove them, so they come along in the artefact. Both
  are small. `pcre2-config` is moved to the staging slice by Buildroot's
  config-script handling, so it isn't in the rootfs.

  ## Only the 8-bit library, and no JIT

  Buildroot builds `libpcre2-8` alone by default; `libpcre2-16` and
  `libpcre2-32` sit behind `BR2_PACKAGE_PCRE2_16` and `BR2_PACKAGE_PCRE2_32`.
  Neither is exposed as a `build_opt` — GLib links the 8-bit library, and
  nothing else in NBPR uses PCRE2 at all.

  JIT (`BR2_PACKAGE_PCRE2_JIT`) is off, matching Buildroot. It's deliberately
  not exposed either: enabling it compiles in the bundled sljit, which adds
  BSD-2-Clause to the package's licence set, and this package's Hex metadata
  declares BSD-3-Clause alone. Exposing the option would let a consumer build
  an artefact whose licensing didn't match what the package says it is.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "pcre2",
    description: "Perl-compatible regular expression library",
    homepage: "https://www.pcre.org/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
