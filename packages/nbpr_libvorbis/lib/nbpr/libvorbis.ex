defmodule NBPR.Libvorbis do
  @moduledoc """
  NBPR package for [`libvorbis`](https://xiph.org/vorbis/) — the reference
  encoder and decoder for Ogg Vorbis, Xiph's patent-free lossy audio codec.

  Ships three libraries under this package's priv dir — `libvorbis.so.0`
  (the codec), `libvorbisenc.so.2` (encoder setup) and `libvorbisfile.so.3`
  (a decoding convenience layer over Ogg streams). `NBPR.Application`
  prepends the directory to `LD_LIBRARY_PATH` at boot so sibling packages
  resolve the sonames. The staging slice carries the headers, `.so` symlinks
  and pkg-config files for cross-compiling a NIF against them.

  Every one of those links `libogg.so.0`, which is why this package depends
  on `:nbpr_libogg` — an nbpr artefact carries only its own Buildroot
  files-list, so a dependency's library has to arrive as its own package.

  For the command-line tools that use this codec — `oggenc`, `oggdec`,
  `ogg123`, `vorbiscomment` — see `:nbpr_vorbis_tools`.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "libvorbis",
    description: "Reference encoder and decoder for the Ogg Vorbis audio codec",
    homepage: "https://xiph.org/vorbis/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
