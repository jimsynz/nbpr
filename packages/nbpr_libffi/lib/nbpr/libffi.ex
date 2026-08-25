defmodule NBPR.Libffi do
  @moduledoc """
  NBPR package for [`libffi`](https://sourceware.org/libffi/) — the portable
  foreign-function interface library.

  Ships `libffi.so.8` under this package's priv dir; `NBPR.Application`
  prepends it to `LD_LIBRARY_PATH` at boot so sibling packages resolve the
  soname. The staging slice carries `ffi.h`, `ffitarget.h`, the `.so` symlink
  and `libffi.pc`, so a NIF can cross-compile against it.

  Packaged because `:nbpr_libglib2` needs it — GObject marshals closure calls
  through libffi — and no Nerves system ships it. Useful on its own to
  anything that has to assemble a call at runtime.

  ## Static exec trampolines are off

  libffi 3.4.2 added a closure allocator that maps one static trampoline table
  twice, so the page holding executable code is never writable. Buildroot
  configures `--disable-exec-static-tramp` regardless, because that scheme
  breaks gobject-introspection — which is the very consumer this package
  exists for.

  So closures fall back to the legacy allocator: a page written as data, then
  `mprotect`ed executable. Nothing on a stock Nerves target objects to that,
  but it's worth knowing if you've hardened the kernel's W^X policy. It isn't
  a kconfig symbol, so it can't be changed through a `build_opt` — only by
  vendoring the Buildroot package.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "libffi",
    description: "Portable foreign-function interface library",
    homepage: "https://sourceware.org/libffi/",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
