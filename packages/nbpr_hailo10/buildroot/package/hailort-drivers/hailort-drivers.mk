################################################################################
#
# hailort-drivers (Hailo-10H)
#
# The v5 PCIe driver builds module `hailo1x_pci.ko` (note the different name
# from the Hailo-8 `hailo_pci.ko` — they don't collide, so an image could in
# principle carry both). Built out-of-tree against the active system kernel,
# same as the Hailo-8 driver.
#
# nerves_system_rpi5 (BR 2026.05) ships a kernel newer than 6.15, where the
# legacy del_timer_sync() API was removed. The base v5.3.0 driver fails to
# compile there ("implicit declaration of del_timer_sync"). Upstream's
# v5.3.0-hotfix-kernel-above-6.15 tag switches to timer_delete_sync() (with a
# compat shim for older kernels), so it builds on both. Same driver ABI as
# v5.3.0, so it pairs with the v5.3.0 libhailort.
#
################################################################################

HAILORT_DRIVERS_VERSION = 5.3.0-hotfix-kernel-above-6.15
HAILORT_DRIVERS_SITE = $(call github,hailo-ai,hailort-drivers,v$(HAILORT_DRIVERS_VERSION))
HAILORT_DRIVERS_LICENSE = GPL-2.0
HAILORT_DRIVERS_LICENSE_FILES = LICENSE
HAILORT_DRIVERS_DEPENDENCIES = linux hailort

HAILORT_DRIVERS_MODULE_SUBDIRS = linux/pcie

define HAILORT_DRIVERS_BUILD_CMDS
	$(MAKE) $(LINUX_MAKE_FLAGS) -C $(LINUX_DIR) M=$(@D)/$(HAILORT_DRIVERS_MODULE_SUBDIRS) modules
endef

define HAILORT_DRIVERS_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/kernel/drivers/media/pci/hailo
	rm -f $(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/kernel/drivers/media/pci/hailo/hailo1x_pci.ko
	$(INSTALL) -D -m 0644 $(@D)/linux/pcie/hailo1x_pci.ko \
		$(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/kernel/drivers/media/pci/hailo/hailo1x_pci.ko
endef

$(eval $(kernel-module))
$(eval $(generic-package))
