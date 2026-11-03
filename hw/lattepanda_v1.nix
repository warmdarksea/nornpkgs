{ config, lib, pkgs, ... }:

# LattePanda v1 (intel cherry trail sbc)
{
  boot.initrd.availableKernelModules = [ "xhci_pci" "usb_storage" "usbhid" "sd_mod" "sdhci_acpi" ];
  boot.kernelModules = [ "kvm-intel" ];

  # boot quirks this board needs
  boot.kernelParams = [ "intel_idle.max_cstate=1" "acpi_osi=\"Windows 2015\"" "nomodeset" ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
