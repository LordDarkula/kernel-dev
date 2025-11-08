sudo dnf group install development-tools

sudo dnf install gcc bc openssl-devel elfutils-libelf-devel ncurses-devel flex bison \
                 dwarves perl-IPC-Cmd qemu-system-x86 qemu-img dracut cpio \
                 busybox glibc-static

# fedora openssl split header
sudo dnf install -y openssl-devel-engine openssl-devel