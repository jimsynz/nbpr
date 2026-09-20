################################################################################
#
# librespot
#
################################################################################

LIBRESPOT_VERSION = 0.8.0
LIBRESPOT_SITE = $(call github,librespot-org,librespot,v$(LIBRESPOT_VERSION))
LIBRESPOT_LICENSE = MIT
LIBRESPOT_LICENSE_FILES = LICENSE
LIBRESPOT_DEPENDENCIES = alsa-lib host-pkgconf

# The default feature set is `native-tls`, `rodio-backend` and `with-libmdns`, and
# rodio drags in every audio backend that the platform has. `--no-default-features`
# is what keeps PulseAudio, JACK and the rest out of the tree, and it takes the other
# two defaults with it, so all three have to be named again.
#
# **A feature set that names no TLS backend does not build.** librespot checks for one
# at compile time, in `librespot-oauth` because that crate comes first, and the error
# is `Either feature "native-tls" (default), "rustls-tls-native-roots" or
# "rustls-tls-webpki-roots" must be enabled for this crate`.
#
# `rustls-tls-webpki-roots` rather than `native-tls`: it is pure Rust, so the build
# links no OpenSSL of the system, and the roots are compiled in rather than read out
# of the rootfs. An appliance that carries no CA bundle therefore still reaches
# Spotify, and the roots move with a firmware upgrade rather than with the rootfs.
# librespot's own guidance names this one for embedded targets.
#
# **`with-libmdns` is what lets a telephone find the device.** It is the pure Rust
# responder; the alternatives need Avahi or `dns-sd`, and neither is in the rootfs.
# **Buildroot builds twice, and the two steps read different variables.**
# `pkg-cargo.mk` gives `cargo build` the `_CARGO_BUILD_OPTS` and then gives
# `cargo install --path ./` the `_CARGO_INSTALL_OPTS`, and an install that names no
# features builds the default set again. The first attempt at this set only the
# first, so the build went through and the install pulled `openssl-sys` back in and
# stopped with `Could not find directory of OpenSSL installation`. Both take the same
# list.
LIBRESPOT_CARGO_FEATURE_OPTS = \
	--no-default-features \
	--features alsa-backend,with-libmdns,rustls-tls-webpki-roots

LIBRESPOT_CARGO_BUILD_OPTS = $(LIBRESPOT_CARGO_FEATURE_OPTS)
LIBRESPOT_CARGO_INSTALL_OPTS = $(LIBRESPOT_CARGO_FEATURE_OPTS)

$(eval $(cargo-package))
