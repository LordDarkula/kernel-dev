# Makefile for building the Linux kernel with GCC 13.4


# Variables
LINUX_DIR := linux
COLLOID_KERNEL_DIR := colloid/tpp/linux-6.3/
KBUILD := kbuild
BUILD_DIR  := $(LINUX_DIR)/$(KBUILD)
COLLOID_BUILD_DIR := $(COLLOID_KERNEL_DIR)/$(KBUILD)
CC_VER := gcc-13
JOBS := $(shell nproc)
KERNEL_IMAGE := $(BUILD_DIR)/arch/x86/boot/bzImage
COLLOID_KERNEL_IMAGE := colloid/tpp/linux-6.3/arch/x86/boot/bzImage
QEMU := qemu-system-x86_64
QEMU_MEM := 4G
QEMU_CPUS := 8
QEMU_DISK := rootfs.img
QEMU_COLLOID_DISK := colloid_rootfs.img
QEMU_EXTRA := -nographic -serial mon:stdio

.PHONY: all colloid config kernel fs boot clean colloid colloid_config colloid_kernel colloid_fs boot_colloid

# Default target: configure then build
all: config kernel fs boot

colloid: colloid_config colloid_kernel colloid_fs boot_colloid

# Step 1: prepare kernel configuration
config:
	mkdir -p $(BUILD_DIR)
	$(MAKE) CC=$(CC_VER) -C $(LINUX_DIR) O=$(CURDIR)/$(BUILD_DIR) defconfig

colloid_config:
	mkdir -p $(COLLOID_BUILD_DIR)
	$(MAKE) CC=$(CC_VER) -C $(COLLOID_KERNEL_DIR) O=$(CURDIR)/$(COLLOID_BUILD_DIR) defconfig

# Step 2: build kernel image and modules, stop at first fatal error
kernel:
	mkdir -p $(BUILD_DIR)
	$(MAKE) CC=$(CC_VER) -C $(LINUX_DIR) O=$(CURDIR)/$(BUILD_DIR) -j"$(JOBS)" bzImage modules --stop

colloid_kernel:
	mkdir -p $(COLLOID_BUILD_DIR)
	$(MAKE) CC=$(CC_VER) -C $(COLLOID_KERNEL_DIR) O=$(CURDIR)/$(COLLOID_BUILD_DIR) -j"$(JOBS)" bzImage modules --stop
	$(MAKE) CC=$(CC_VER) -C $(COLLOID_KERNEL_DIR) O=$(CURDIR)/$(COLLOID_BUILD_DIR) -j"$(JOBS)" modules_install --stop

# Optional: clean up build artifacts
clean:
	@echo "==> Cleaning kernel tree..."
	cd $(LINUX_DIR) && \
	make clean
	@echo "==> Clean complete. Returned to parent directory."

fs:
	chmod +x build_rootfs.sh && ./build_rootfs.sh

colloid_fs:
	chmod +x build_colloid_rootfs.sh && ./build_colloid_rootfs.sh

boot:
	@echo "==> Booting kernel in QEMU..."
	$(QEMU) \
	 	-enable-kvm \
		-cpu host \
		-machine q35,accel=kvm \
		-kernel $(KERNEL_IMAGE) \
		-initrd $(QEMU_DISK) \
		-smp $(QEMU_CPUS) \
		-m $(QEMU_MEM) \
		-object memory-backend-ram,id=mem0,size=2G \
		-object memory-backend-ram,id=mem1,size=2G \
		-numa node,nodeid=0,memdev=mem0 \
		-numa node,nodeid=1,memdev=mem1 \
		-append "console=ttyS0" \
		$(QEMU_EXTRA)
	@echo "==> QEMU session ended."

boot_colloid:
	@echo "==> Booting colloid kernel in QEMU..."
	$(QEMU) \
	 	-enable-kvm \
		-cpu host \
		-machine q35,accel=kvm \
		-kernel $(COLLOID_KERNEL_IMAGE) \
		-initrd $(QEMU_COLLOID_DISK) \
		-smp $(QEMU_CPUS) \
		-m $(QEMU_MEM) \
		-object memory-backend-ram,id=mem0,size=2G \
		-object memory-backend-ram,id=mem1,size=2G \
		-numa node,nodeid=0,memdev=mem0 \
		-numa node,nodeid=1,memdev=mem1 \
		-append "console=ttyS0" \
		$(QEMU_EXTRA)
	@echo "==> QEMU session ended."
