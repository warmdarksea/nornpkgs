{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ./amd.nix
    ./amdgpu.nix
    ./uhk.nix
  ];

  # ty https://discourse.nixos.org/t/creating-a-bootable-usb-with-custom-firmware-support/15343
  # boot.kernelParams = ["amdgpu.backlight=0" "acpi_backlight=none"];
  boot.kernelParams = ["acpi_backlight=native"];
  boot.extraModulePackages = with config.boot.kernelPackages; [ acpi_call ];
  boot.kernelModules = ["acpi_call"];
  hardware.enableRedistributableFirmware = true;

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "usb_storage" "sd_mod" ];

  #hardware.video.hidpi.enable = true;
}