{ config, lib, pkgs, ... }:

# mausoleum: amd desktop (with an mptsas hba)
{
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "mptsas" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
