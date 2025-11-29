# Booting Alternate Linux Kernels

After building and installing a kernel, you can boot them using GRUB.

Use the following command to see the list of kernels listed in GRUB.
```bash
grep "menuentry" /boot/grub/grub.cfg
```
The options will either be global or in a submenu, maybe titled "Advanced options for Ubuntu"
If the menu options are located in a submenu, you will need to include it in the grub path
```bash
$ sudo grub-reboot "Advanced options for Ubuntu>Ubuntu, with Linux 6.3.0-colloid"
```
If not, you can just use the kernel name.
```bash
$ sudo grub-reboot "Ubuntu, with Linux 6.3.0-colloid"
```

Then just reboot.
```bash
$ sudo reboot
```

