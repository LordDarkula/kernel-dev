#!/bin/bash
set -e

sudo dnf install gcc bc openssl-devel elfutils-libelf-devel ncurses-devel flex bison \
                 dwarves perl-IPC-Cmd qemu-system-x86 qemu-img dracut cpio \
                 busybox glibc-static

# ================================
# 1. Create directory structure
# ================================
echo "[*] Creating rootfs directory structure..."
rm -rf rootfs
rm -f rootfs.img
mkdir -p rootfs/{bin,sbin,etc,proc,sys,dev,tmp}
mkdir -p rootfs/usr/lib
mkdir -p rootfs/{lib,lib64,usr/lib64}

# cd rootfs
# cp -av /usr/lib/lib[mc].so.6 usr/lib/
# cp -av /usr/lib/ld-linux.so.2 usr/lib/
# cp -av /usr/lib/ld-musl-x86_64.so.1 usr/lib/
# cd ..

cp -a /usr/lib64/libc.so.6 /usr/lib64/libm.so.6 /usr/lib64/libresolv.so.2 rootfs/usr/lib64/

# ================================
# 2. Download and build BusyBox
# ================================
if [ ! -f busybox-1.36.1.tar.bz2 ]; then
    echo "[*] Downloading BusyBox..."
    wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2
fi

echo "[*] Extracting BusyBox..."
rm -rf busybox-1.36.1
tar xf busybox-1.36.1.tar.bz2
cd busybox-1.36.1

echo "[*] Applying default config..."
make distclean
make defconfig

# Disable WERROR (warnings as errors)
echo "[*] Disabling warnings as errors..."
sed -i 's/^CONFIG_WERROR=y/# CONFIG_WERROR is not set/' .config

# Optionally disable tc networking applet (recommended)
sed -i 's/^CONFIG_TC=y/# CONFIG_TC is not set/' .config
sed -i 's/^CONFIG_TC_/&is not set/' .config

sed -i 's/#CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

echo "[*] Building BusyBox..."
make CONFIG_STATIC=y -j"$(nproc)"

echo "[*] Installing BusyBox into rootfs..."
make CONFIG_STATIC=y CONFIG_PREFIX=../rootfs install


cd ..

# ================================
# 3. Create minimal init script
# ================================
echo "[*] Creating /init..."
cat > rootfs/init << 'EOF'
#!/bin/sh

# Initialize system
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || mount -t tmpfs none /dev

echo "================================="
echo "   Custom Linux Kernel Booted    "
echo "================================="

# Start interactive shell
exec /bin/sh
EOF

chmod +x rootfs/init

cp rootfs/init rootfs/sbin/
chmod +x rootfs/sbin/init

cd busybox-1.36.1
make CONFIG_STATIC=y CONFIG_PREFIX=../rootfs install
cd ..

# ================================
# 4. Create initramfs (cpio archive)
# ================================
echo "[*] Creating initramfs image rootfs.img..."
cd rootfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../rootfs.img
cd ..

echo "[+] Done! Initramfs is rootfs.img"
echo "[+] You can now boot it with QEMU using:"
echo "qemu-system-x86_64 -kernel linux/arch/x86/boot/bzImage -initrd rootfs.img -append \"console=ttyS0\" -nographic -m 512M"

