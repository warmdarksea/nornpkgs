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

#  services.xserver.synaptics.enable = true;
#  services.xserver.synaptics.tapButtons = false;
  #services.xserver.libinput.mouse.tapping = false;
  #services.xserver.libinput.touchpad.tapping = false;
  #environment.etc."udev/hwdb.d/10-local.hwdb".text = ''
  #  libinput:name:SynPS/2 Synaptics TouchPad:dmi:*svnLENOVO:*:pvrThinkPadX230Tablet*
  #  LIBINPUT_MODEL_LENOVO_X230=1
  #'';
  services.xserver.wacom.enable = true;
  services.xserver.modules = [pkgs.xorg.xf86inputlibinput];
}