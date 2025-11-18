# Makefile for building the Linux kernel with GCC 13.4
# It enters the 'linux' directory, builds, then returns to the parent.

# Variables
LINUX_DIR := linux
CC_VER := gcc-13
JOBS := $(shell nproc)
KERNEL_IMAGE := $(LINUX_DIR)/arch/x86/boot/bzImage
COLLOID_KERNEL_IMAGE := colloid/tpp/linux-6.3/arch/x86/boot/bzImage
QEMU := qemu-system-x86_64
QEMU_MEM := 4G
QEMU_CPUS := 8
QEMU_DISK := rootfs.img
QEMU_EXTRA := -nographic -serial mon:stdio

.PHONY: all colloid config kernel fs boot clean colloid colloid_config colloid_kernel colloid_fs boot_colloid

# Default target: configure then build
all: config kernel fs boot

colloid: colloid_config colloid_kernel colloid_fs boot_colloid

# Step 1: prepare kernel configuration
config:
	@echo "==> Entering $(LINUX_DIR) to run olddefconfig..."
	cd $(LINUX_DIR) && \
	make CC=$(CC_VER) mrproper olddefconfig
	@echo "==> Returning to parent directory."

colloid_config:
	cs colloid/tpp/linux-6.3 && \
	make CC=$(CC_VER) olddefconfig
	@echo "Edit .config to set -colloid option in CONFIG_LOCALVERSION"

# Step 2: build kernel image and modules, stop at first fatal error
kernel:
	@echo "==> Building kernel with $(CC_VER)..."
	cd $(LINUX_DIR) && \
	make CC=$(CC_VER) -j"$(JOBS)" bzImage modules --stop
	@echo "==> Build finished. Returned to parent directory."

colloid_kernel:
	@echo "==> Building colloid + TPP kernel with $(CC_VER)"
	cd colloid/tpp/linux-6.3 && \
	make CC=$(CC_VER) -j"$(JOBS)" bzImage modules --stop && \
	make CC=$(CC_VER) modules_install

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
