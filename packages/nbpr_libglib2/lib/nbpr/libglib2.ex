defmodule NBPR.Libglib2 do
  @moduledoc """
  NBPR package for [`GLib`](https://gitlab.gnome.org/GNOME/glib) — the
  low-level utility library underneath GTK, GStreamer and much of the GNOME
  stack.

  Ships `libglib-2.0.so.0` and its siblings — `libgobject-2.0.so.0`,
  `libgio-2.0.so.0`, `libgmodule-2.0.so.0`, `libgthread-2.0.so.0` — under this
  package's priv dir; `NBPR.Application` prepends it to `LD_LIBRARY_PATH` at
  boot so sibling packages resolve the sonames. The staging slice carries the
  headers and pkg-config files, so a NIF can cross-compile against them.

  Packaged because `:nbpr_libvips` needs it: libvips builds its entire
  operation system on GObject, and every `VipsImage` is a `GObject`. No Nerves
  system ships GLib.

  This is the biggest package in that chain by a wide margin, and it is the
  reason `:nbpr_libvips` costs what it does in rootfs space. If all you want
  is one image resized, weigh it against `:nbpr_imagemagick`, which links
  nothing like this.

  ## What comes along

  Buildroot deletes the developer tooling from the rootfs after install —
  `glib-compile-schemas`, `glib-mkenums`, `gdbus-codegen`, `gobject-query` and
  friends are host-side concerns. What survives into `usr/bin` is the runtime
  handful: `gio`, `gio-querymodules`, `gapplication`, `gdbus`, `gresource` and
  `gsettings`.

  ## Dependencies not in this package's deps

  GLib `select`s four Buildroot packages. Two are here — `:nbpr_libffi` and
  `:nbpr_pcre2`. The other two aren't, deliberately:

    * **zlib** is already in the Nerves rootfs as `libz.so.1`, so there's no
      `:nbpr_zlib` to depend on — the same situation `NBPR.Libpng` is in.
    * **libiconv** is selected only `if !BR2_ENABLE_LOCALE`. Every Nerves
      system enables locale, so glibc and musl provide `iconv` themselves and
      the package is never pulled in.

  Buildroot also builds against `util-linux`'s libmount when
  `BR2_PACKAGE_UTIL_LINUX_LIBMOUNT` is set. No Nerves system sets it — the
  `libblkid`/`libuuid` in the rootfs come from e2fsprogs — so GIO is
  configured `-Dlibmount=disabled` and its mount monitoring reads
  `/proc/self/mountinfo` rather than going through libmount.

  ## GSettings schemas won't be compiled

  Buildroot compiles the GSettings schema cache in a `target-finalize` hook,
  which runs once over the merged rootfs at the end of a full system build.
  NBPR never gets there — it harvests each package's own install and applies
  Buildroot's finalize *recipe* to that, not the per-package hooks. So no
  `gschemas.compiled` is produced, and the schema sources Buildroot would have
  removed are still in `usr/share/glib-2.0/schemas`.

  GLib itself installs no schemas, only the DTD, so nothing here is broken by
  it. It matters the moment you package something that does ship a schema:
  `g_settings_new()` aborts on a schema it can't find in the compiled cache,
  and that cache will not exist. Compile it into your own firmware overlay
  instead.

  ## GIO modules

  Buildroot pins GIO's module directory to the absolute path
  `/usr/lib/gio/modules`, which nbpr's priv-dir install never populates. GLib
  ships no modules of its own, so the scan finds nothing and costs nothing.
  The consequence is for later: a package providing a GIO extension — TLS
  support via glib-networking, say — would install it under its own priv dir
  where GIO will not look. See `NBPR.Libao` for the same problem in a package
  where it does bite.

  ## No introspection

  `BR2_PACKAGE_GOBJECT_INTROSPECTION` is off, so no `.typelib` files are
  generated and the GObject introspection bindings — libvips' Python and Ruby
  APIs among them — can't be used. On a target with no Python interpreter that
  is no loss.
  """

  use NBPR.BrPackage,
    version: 1,
    br_package: "libglib2",
    description: "Low-level core utility library behind GTK and GNOME",
    homepage: "https://gitlab.gnome.org/GNOME/glib",
    artifact_sites: [{:ghcr, "ghcr.io/jimsynz/nbpr"}]
end
