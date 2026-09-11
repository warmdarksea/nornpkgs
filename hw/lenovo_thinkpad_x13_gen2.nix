{ config, lib, pkgs, modulesPath, ... }:

# thinkpad x13 gen2 amd. used together with
# nixos-hardware.nixosModules.lenovo-thinkpad-x13-amd; this is just the
# machine scan.
{
  boot.initrd.availableKernelModules = [ "nvme" "ehci_pci" "xhci_pci" "usbhid" "usb_storage" "uas" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # dormant experiments from the pre-refactor version of this file; opt back
  # in if the backlight/keyboard bits are still wanted:
  # imports = [ ./amdgpu.nix ./uhk.nix ];
  # ty https://discourse.nixos.org/t/creating-a-bootable-usb-with-custom-firmware-support/15343
  # boot.kernelParams = ["acpi_backlight=native"];
  # boot.extraModulePackages = with config.boot.kernelPackages; [ acpi_call ];
  # boot.kernelModules = ["acpi_call"];
}
