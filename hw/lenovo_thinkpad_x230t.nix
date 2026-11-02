{ config, lib, pkgs, ... }:

{
  imports = [
    ../hw/intel.nix
    ../hw/intelgpu.nix
  ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ehci_pci" "ahci" "usb_storage" "sd_mod" "sdhci_pci" ];
  hardware.enableAllFirmware = true;

  nix.maxJobs = lib.mkDefault 4;
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  services.logind.lidSwitch = "ignore";

  services.xserver.wacom.enable = true;
  services.xserver.modules = [pkgs.xorg.xf86inputlibinput];
}