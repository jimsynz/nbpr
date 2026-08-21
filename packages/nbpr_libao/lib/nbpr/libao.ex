defmodule NBPR.Libao do
  @moduledoc """
  NBPR package for [`libao`](https://www.xiph.org/ao/) — Xiph's thin
  cross-platform audio output library, the layer `ogg123` plays through.

  Ships `libao.so.4` under this package's priv dir, which `NBPR.Application`
  prepends to `LD_LIBRARY_PATH` at boot, plus whichever output plugins
  Buildroot built under `usr/lib/ao/plugins-4/`. The staging slice carries
  the headers, the `.so` symlink and `ao.pc`.

  Nothing links libao today except `:nbpr_vorbis_tools`, which is why this
  package exists — an nbpr artefact ships only its own Buildroot files-list,
  so `ogg123`'s `libao.so.4` has to arrive as its own package.

  ## Live audio output does not work yet

  libao finds its output plugins by `opendir` on a path fixed at compile
  time — `/usr/lib/ao/plugins-4`, since that's where Buildroot's `libdir`
  points. nbpr artefacts install under the package's `priv/`, not at rootfs
  paths, and there's no environment variable to redirect the search
  (`ao_load_plugins/0` in libao's `audio_out.c` takes `AO_PLUGIN_PATH`
  verbatim from the build). So on a Nerves target the plugin directory the
  library looks in is empty, and only the drivers compiled into libao itself
  are available:

    * `wav`, `au`, `raw` — write an audio file
    * `null` — discard

  Which is enough for `ogg123 -d wav -f out.wav`, and not enough to make a
  speaker produce sound. Fixing it needs the artefact's plugin directory
  installed at its rootfs path rather than into `priv/` — the `rootfs/`
  artefact slice `NBPR.Pack` already carries for kernel modules, which the
  Buildroot harvest step doesn't populate yet.

  ## Which plugin gets built

  Buildroot enables libao's ALSA plugin when the system has `alsa-lib` and
  falls back to OSS when it doesn't, so the artefact differs per target:
  `libalsa.so` on the Raspberry Pi systems, `liboss.so` on `bbb`, `x86_64`
  and `trellis`. Neither loads today, per above.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "libao",
    description: "Cross-platform audio output library",
    homepage: "https://www.xiph.org/ao/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
