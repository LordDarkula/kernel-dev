#!/bin/bash
set -e

# ================================
# 1. Create directory structure
# ================================
echo "[*] Creating colloid_rootfs directory structure..."
rm -rf colloid_rootfs
rm -f colloid_rootfs.img
mkdir -p colloid_rootfs/{bin,sbin,etc,proc,sys,dev,tmp}
mkdir -p colloid_rootfs/usr/lib
mkdir -p colloid_rootfs/{lib,lib64,usr/lib64}
mkdir -p colloid_rootfs/lib/modules

cp -a /usr/lib64/libc.so.6 /usr/lib64/libm.so.6 || true
cp -a /usr/lib64/libresolv.so.2 || true
cp -a colloid_rootfs/usr/lib64/ || true
cp -a /usr/lib64/ld-linux-x86-64.so.2 || true

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

echo "[*] Installing BusyBox into colloid_rootfs..."
make CONFIG_STATIC=y CONFIG_PREFIX=../colloid_rootfs install


cd ..

# ================================
# 3. Create minimal init script
# ================================
echo "[*] Creating /init..."
cat > colloid_rootfs/init << 'EOF'
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

chmod +x colloid_rootfs/init

cp colloid_rootfs/init colloid_rootfs/sbin/
chmod +x colloid_rootfs/sbin/init

cp tinker-linux/memater colloid_rootfs/usr/bin/
chmod +x colloid_rootfs/usr/bin/memater

cp tinker-linux/setup-cgroups-root.sh colloid_rootfs/
chmod +x colloid_rootfs/setup-cgroups-root.sh

cp colloid/tpp/tierinit/tierinit.ko colloid_rootfs/lib/modules/
chmod +x colloid_rootfs/lib/modules/tierinit.ko
cp colloid/tpp/colloid-mon/colloid-mon.ko colloid_rootfs/lib/modules/
chmod +x colloid_rootfs/lib/modules/colloid-mon.ko

cd busybox-1.36.1
make CONFIG_STATIC=y CONFIG_PREFIX=../colloid_rootfs install
cd ..

# ================================
# 4. Create initramfs (cpio archive)
# ================================
echo "[*] Creating initramfs image colloid_rootfs.img..."
cd colloid_rootfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../colloid_rootfs.img
cd ..

echo "[+] Done! Initramfs is colloid_rootfs.img"
echo "[+] You can now boot it with QEMU using:"
echo "qemu-system-x86_64 -kernel linux/arch/x86/boot/bzImage -initrd colloid_rootfs.img -append \"console=ttyS0\" -nographic -m 512M"

