{ config, lib, pkgs, ... }:

# GPD Pocket 3 (tiger lake). used together with
# nixos-hardware.nixosModules.gpd-pocket-3, which handles the rotated
# display & touch matrix; this is just the machine scan.
{
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
