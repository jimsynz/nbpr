defmodule NBPR.Libogg do
  @moduledoc """
  NBPR package for [`libogg`](https://xiph.org/ogg/) — the reference
  implementation of the Ogg container format, the wrapper every Xiph codec
  stores its packets in.

  Ships `libogg.so.0` under this package's priv dir; `NBPR.Application`
  prepends it to `LD_LIBRARY_PATH` at boot so sibling packages resolve the
  soname. The staging slice carries the headers, the `.so` symlink and
  `ogg.pc`, so a NIF can cross-compile against it.

  No stock Nerves system carries libogg, and an nbpr artefact only ships its
  own Buildroot files-list — so every package linking it needs this one in
  the firmware too. Current consumers: `:nbpr_libvorbis` (Buildroot's
  libvorbis `select`s libogg unconditionally), `:nbpr_vorbis_tools`, and
  `:nbpr_flac` when its `ogg` option is on.

  Containers, not codecs: nothing here encodes or decodes audio. Reach for
  `:nbpr_libvorbis` or `:nbpr_flac` for that.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "libogg",
    description: "Reference implementation of the Ogg container format",
    homepage: "https://xiph.org/ogg/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
