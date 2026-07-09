################################################################################
#
# hailort-firmware (Hailo-10H)
#
# The 10H ships a full boot bundle (u-boot SPL + signed DTBs, SCU firmware,
# fitImage, image-fs, customer certificate) which the hailo1x_pci driver pushes
# to the SOC over PCIe at probe time.
#
# The driver calls request_firmware() for "hailo/hailo10h/<file>"
# (customer_certificate.bin, scu_fw.bin, u-boot-<board-SKU>.dtb.signed,
# u-boot-spl.bin, fitImage, image-fs), i.e. it looks under
# /lib/firmware/hailo/hailo10h/ — not a versioned subdir. Verified on a
# Hailo-10H: the bundle boots the SOC and creates /dev/h1x-0.
#
################################################################################

HAILORT_FIRMWARE_VERSION = 5.3.0
HAILORT_FIRMWARE_SITE = https://hailo-hailort.s3.eu-west-2.amazonaws.com/Hailo10H/$(HAILORT_FIRMWARE_VERSION)/FW
HAILORT_FIRMWARE_SOURCE = hailo10h_fw.tar.gz
HAILORT_FIRMWARE_LICENSE = Proprietary
HAILORT_FIRMWARE_REDISTRIBUTE = NO

HAILORT_FIRMWARE_FW_DIR = $(TARGET_DIR)/lib/firmware/hailo/hailo10h

# Copy only the real firmware blobs. Excluding ALL dotfiles (not just .stamp*)
# is important: Buildroot drops its own per-package snapshot files
# (.files-list*.before, .applied_patches_list) into $(@D), and sweeping those
# into the rootfs both ships junk AND lands a `.files-list.before` inside the
# target tree, which corrupts the per-package files-list diff so the firmware
# (and neighbouring packages') files get dropped from the harvested artefact.
define HAILORT_FIRMWARE_INSTALL_TARGET_CMDS
	mkdir -p $(HAILORT_FIRMWARE_FW_DIR)
	cd $(@D) && find . -maxdepth 1 -type f ! -name '.*' \
		-exec $(INSTALL) -D -m 0644 {} $(HAILORT_FIRMWARE_FW_DIR)/ \;
endef

$(eval $(generic-package))
