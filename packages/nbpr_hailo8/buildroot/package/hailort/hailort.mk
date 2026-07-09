################################################################################
#
# hailort
#
################################################################################

HAILORT_VERSION = 4.24.0
HAILORT_SITE = $(call github,hailo-ai,hailort,v$(HAILORT_VERSION))
HAILORT_LICENSE = MIT
HAILORT_LICENSE_FILES = hailort/LICENSE hailort/LICENSE-3RD-PARTY.md
HAILORT_SUPPORTS_IN_SOURCE_BUILD = NO
HAILORT_INSTALL_STAGING = YES

HAILORT_DEPENDENCIES = spdlog_hailort

# HailoRT vendors and builds its own protobuf (v21.12). It links
# libhailort against libprotobuf-lite dynamically, but doesn't install
# the shared object into the target. Copy it out of the build tree so
# libhailort can resolve it at runtime. The soname (.so.32) tracks the
# bundled protobuf version; bump it alongside HAILORT_VERSION if protobuf
# changes.
define HAILORT_INSTALL_PROTOBUF_LITE
	$(INSTALL) -D -m 0644 $(@D)/buildroot-build/_deps/protobuf-build/libprotobuf-lite.so.32 \
		$(TARGET_DIR)/usr/lib/libprotobuf-lite.so.32
endef

HAILORT_POST_INSTALL_TARGET_HOOKS += HAILORT_INSTALL_PROTOBUF_LITE

$(eval $(cmake-package))
