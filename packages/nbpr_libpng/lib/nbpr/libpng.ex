defmodule NBPR.Libpng do
  @moduledoc """
  NBPR package for [`libpng`](http://www.libpng.org/) — the reference library
  for reading and writing PNG images.

  Ships `libpng16.so.16` under this package's priv dir; `NBPR.Application`
  prepends it to `LD_LIBRARY_PATH` at boot so sibling packages resolve the
  soname. The staging slice carries the headers, the `.so` symlink and
  `libpng.pc`, so a NIF can cross-compile against it.

  Packaged because no Nerves system ships libpng — a stock rootfs carries
  `libz.so.1` and nothing else from the image-library set — while anything
  handling PNG needs it. Useful on its own to a NIF that wants to decode PNG
  without shelling out.

  ## zlib

  Buildroot's libpng `select`s zlib, which every Nerves system already builds
  (Erlang's `zlib` module needs it), so `libz.so.1` resolves from the base
  system and there's no `:nbpr_zlib` to depend on. Nothing to configure.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "libpng",
    description: "Library for reading and writing PNG images",
    homepage: "http://www.libpng.org/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
