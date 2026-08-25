defmodule NBPR.Expat do
  @moduledoc """
  NBPR package for [`expat`](https://libexpat.github.io/) — the stream-oriented
  XML parser.

  Ships `libexpat.so.1` under this package's priv dir; `NBPR.Application`
  prepends it to `LD_LIBRARY_PATH` at boot so sibling packages resolve the
  soname. The staging slice carries `expat.h`, `expat_external.h`, the `.so`
  symlink, `expat.pc` and the CMake config, so a NIF can cross-compile against
  it.

  Packaged because `:nbpr_libvips` needs it — libvips parses its XML image
  metadata with expat — and no Nerves system ships it. Useful on its own to
  anything wanting a pull parser outside the BEAM.

  Buildroot configures `--without-xmlwf`, so the `xmlwf` well-formedness
  checker isn't built and this package is the library alone.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "expat",
    description: "Stream-oriented XML parser library",
    homepage: "https://libexpat.github.io/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
