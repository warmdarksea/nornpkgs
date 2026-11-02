{ config, lib, pkgs, modulesPath, ... }:

# thinkpad x13 gen2 amd. used together with
# nixos-hardware.nixosModules.lenovo-thinkpad-x13-amd; this is just the
# machine scan.
{
  boot.initrd.availableKernelModules = [ "nvme" "ehci_pci" "xhci_pci" "usbhid" "usb_storage" "uas" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
