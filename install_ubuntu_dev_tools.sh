sudo apt update

# necessary dependencies for building the kernel
sudo apt install libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf llvm

# install gcc-13 (necessary for building kernel 6.6)
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt update
sudo apt install gcc-13

# install qemu
sudo apt install qemu-system
