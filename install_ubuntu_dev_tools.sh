packages=(
    libncurses-dev
    gawk
    flex
    bison
    openssl
    libssl-dev
    dkms
    libelf-dev
    libudev-dev
    libpci-dev
    autoconf
    llvm
		debhelper
		qemu-system

)
sudo apt update

for pkg in "${packages[@]}"; do
    echo "Installing $pkg..."
    sudo apt-get install -y --no-install-recommends "$pkg" || \
        echo "Skipping: $pkg not found or already satisfied"
done

# install gcc-13 (necessary for building kernel 6.6)
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt update -y
sudo apt install -y gcc-13

