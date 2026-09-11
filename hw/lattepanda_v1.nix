{ config, lib, pkgs, ... }:

# LattePanda v1 (intel cherry trail sbc)
{
  boot.initrd.availableKernelModules = [ "xhci_pci" "usb_storage" "usbhid" "sd_mod" "sdhci_acpi" ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
