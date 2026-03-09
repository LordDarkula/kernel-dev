# Kernel Development Environment
These scripts facilitate kernel development, including configuring, compiling, and booting.

## Initial Setup
Run the following scripts to clone the necessary repositories and install the build tools.

```bash
chmod +x scripts/clone_repos.sh

# if you do not have ssh access, use https option instead
./scripts/clone_repos.sh ssh
```

### Build Tool Installation
The build tool installation scripts are distro-specific. We support both `debian` and `fedora`.

On debian
```bash
chmod +x scripts/install_ubuntu_dev_tools.sh
sudo ./scripts/install_ubuntu_dev_tools.sh
```

Fedora does not ship with the correct version of gcc, so it must be compiled.
```bash
chmod +x scripts/install_gcc_13.sh
sudo ./scripts/install_gcc_13.sh
```
Then you can install the fedora build tools
```bash
chmod +x scripts/install_fedora_dev_tools.sh
sudo ./scripts/install_fedora_dev_tools.sh
```

## Compiling the Kernel
The `Makefile` in the root directory contains the commands for configuring and building the versions of the kernel
needed for the experiments. The appropriate config files are located in `kernel-configs/`.

### Colloid Kernel
This command copies the correct config file and compiles the kernel with the necessary options.
```bash
make colloid_config_cloudlab
```

This will add the new kernel to debian's boot menu.
```bash
make colloid_deb
```

## Booting the Kernel
Directions to boot the kernel are stored in [docs/BOOT_KERNEL.md](docs/BOOT_KERNEL.md).

## Setting up Modes
In order to run experiments, you must first enable TPP (default NUMA migration) or colloid within the compiled kernel.

Enable TPP
```bash
chmod +x scripts/enable_tpp.sh
sudo ./scripts/enable_tpp.sh
```

Enable Colloid
```bash
chmod +x scripts/enable_colloid.sh
sudo ./scripts/enable_colloid.sh
```
