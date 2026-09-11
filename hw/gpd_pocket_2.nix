{ config, lib, pkgs, ... }:

# GPD Pocket 2 (amber lake). no upstream nixos-hardware module for this
# one, so everything lives here.
{
  boot.initrd.availableKernelModules = [ "xhci_pci" "usb_storage" "usbhid" "sd_mod" "sdhci_pci" ];
  boot.kernelModules = [ "kvm-intel" ];

  # portrait panel; rotate the console
  boot.kernelParams = [ "video=efifb" "fbcon=rotate:1" ];
  console.font = "latarcyrheb-sun32";

  hardware.graphics.enable = true;
  # "i915" is a kernel driver, not an X11 driver; modesetting is the right one
  services.xserver.videoDrivers = [ "modesetting" ];

  # hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.wireless-regdb ]; # is this necessary?

  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
