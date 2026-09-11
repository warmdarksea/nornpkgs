{ config, lib, pkgs, ... }:

# asus eee pc (i686, 2GB ram)
{
  boot.initrd.availableKernelModules = [ "uhci_hcd" "ehci_pci" "ata_piix" "usb_storage" "sd_mod" "adiantum" "chacha_generic" "poly1305_generic" "nhpoly1305" ];
  boot.initrd.kernelModules = [ "loop" ];

  # low-memory tuning
  boot.kernelParams = [ "ramdisk_size=64000" "zfs_prefetch_disable=1" "zfs_nocacheflush=1" "vmalloc=512M" ];

  hardware.enableRedistributableFirmware = true;

  services.xserver.videoDrivers = [ "intel" ];
}
