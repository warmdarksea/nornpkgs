{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ./amd.nix
  ];

  boot.kernelParams = ["nomodeset"];
  #boot.initrd.availableKernelModules = [ "uhci_hcd" "ehci_pci" "ahci" "pata_jmicron" "mptsas" "usb_storage" "usbhid" "floppy" "sd_mod" "adiantum" "chacha_generic" "poly1305_generic" "nhpoly1305" ];
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "mptsas" "usb_storage" "usbhid" "sd_mod" "pata_jmicron" "adiantum" "chacha_generic" "poly1305_generic" "nhpoly1305" ];

  hardware.enableRedistributableFirmware = true;

  nix.settings.max-jobs = lib.mkDefault 12;
}