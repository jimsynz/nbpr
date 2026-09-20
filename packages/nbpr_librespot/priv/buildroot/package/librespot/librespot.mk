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

# The default feature set builds every audio backend, and each one drags in
# another library that a Nerves system does not carry. ALSA is the one that this
# board has, and `--no-default-features` is what keeps PulseAudio, JACK, GStreamer
# and the rest out of the tree.
LIBRESPOT_CARGO_BUILD_OPTS = --no-default-features --features alsa-backend

$(eval $(cargo-package))
