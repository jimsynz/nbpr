################################################################################
#
# hailort (Hailo-10H / HailoRT v5)
#
# 0001-Patch-for-Nerves.patch is the v5.3.0 port of the Hailo-8 Nerves patch:
# it redirects spdlog to the Buildroot-built shared lib, neutralises the empty
# Protobuf_INCLUDE_DIRS genex on the proto targets (including v5's new
# genai_scheme_proto), and installs+exports hef/profiler/scheduler_mon_proto so
# install(EXPORT HailoRTTargets) succeeds. The bundled protobuf soname is
# libprotobuf-lite.so.32 (v5.3.0 pins protobuf v21.12), copied out below.
#
################################################################################

HAILORT_VERSION = 5.3.0
HAILORT_SITE = $(call github,hailo-ai,hailort,v$(HAILORT_VERSION))
HAILORT_LICENSE = MIT
HAILORT_LICENSE_FILES = hailort/LICENSE hailort/LICENSE-3RD-PARTY.md
HAILORT_SUPPORTS_IN_SOURCE_BUILD = NO
HAILORT_INSTALL_STAGING = YES

HAILORT_DEPENDENCIES = spdlog_hailort

# Build memory: HailoRT's CMake Release build compiles a lot of heavy C++ at -O3
# (the genai serializer, minja, protobuf-generated units, and hailortcli), which
# spikes per-compiler RAM and, combined with high parallelism, triggers the
# OOM-killer. Drop to -O2 and let GCC garbage-collect its own heap far more
# aggressively. Both cut peak memory with negligible runtime cost: libhailort
# only orchestrates inference — the actual compute runs on the accelerator.
HAILORT_MEM_CFLAGS = -O2 -DNDEBUG --param ggc-min-expand=10 --param ggc-min-heapsize=32768
HAILORT_CONF_OPTS += \
	-DCMAKE_CXX_FLAGS_RELEASE="$(HAILORT_MEM_CFLAGS)" \
	-DCMAKE_C_FLAGS_RELEASE="$(HAILORT_MEM_CFLAGS)"

# See note above: HailoRT vendors protobuf v21.12 and links libhailort against
# libprotobuf-lite dynamically without installing it. Copy it out of the build
# tree so libhailort can resolve it at runtime; the soname tracks the bundled
# protobuf version, so bump it if HailoRT changes its pin.
define HAILORT_INSTALL_PROTOBUF_LITE
	$(INSTALL) -D -m 0644 $(@D)/buildroot-build/_deps/protobuf-build/libprotobuf-lite.so.32 \
		$(TARGET_DIR)/usr/lib/libprotobuf-lite.so.32
endef

HAILORT_POST_INSTALL_TARGET_HOOKS += HAILORT_INSTALL_PROTOBUF_LITE

$(eval $(cmake-package))
