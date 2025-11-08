# Makefile for building the Linux kernel with GCC 13.4
# It enters the 'linux' directory, builds, then returns to the parent.

# Variables
LINUX_DIR := linux
CC_VER := gcc-13.4
JOBS := $(shell nproc)
KERNEL_IMAGE := $(LINUX_DIR)/arch/x86/boot/bzImage
QEMU := qemu-system-x86_64
QEMU_MEM := 3G
QEMU_CPUS := 8
QEMU_DISK := rootfs.img
QEMU_EXTRA := -nographic -serial mon:stdio

.PHONY: all config build clean

# Default target: configure then build
all: config build_kernel

# Step 1: prepare kernel configuration
config:
	@echo "==> Entering $(LINUX_DIR) to run olddefconfig..."
	cd $(LINUX_DIR) && \
	make CC=$(CC_VER) mrproper olddefconfig
	@echo "==> Returning to parent directory."

# Step 2: build kernel image and modules, stop at first fatal error
build_kernel:
	@echo "==> Building kernel with $(CC_VER)..."
	cd $(LINUX_DIR) && \
	make CC=$(CC_VER) -j"$(JOBS)" bzImage modules --stop
	@echo "==> Build finished. Returned to parent directory."

# Optional: clean up build artifacts
clean:
	@echo "==> Cleaning kernel tree..."
	cd $(LINUX_DIR) && \
	make clean
	@echo "==> Clean complete. Returned to parent directory."

build_image:
	chmod +x build_rootfs.sh && ./build_rootfs.sh

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
		-object memory-backend-ram,id=mem1,size=1G \
		-numa node,nodeid=0,memdev=mem0 \
		-numa node,nodeid=1,memdev=mem1 \
		-append "console=ttyS0" \
		$(QEMU_EXTRA)
	@echo "==> QEMU session ended."