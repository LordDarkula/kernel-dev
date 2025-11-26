sudo apt update -y

# necessary dependencies for building the kernel
sudo apt install -y libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf llvm

# install gcc-13 (necessary for building kernel 6.6)
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt update -y
sudo apt install -y gcc-13

# required for building kernel as debian package
sudo apt install -y debhelper

# install qemu
sudo apt install -y qemu-system
