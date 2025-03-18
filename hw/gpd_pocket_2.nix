{ config, lib, pkgs, ... }:

{
  imports = [
    ./intel.nix
    ./intelgpu.nix
    ./hidpi.nix
  ];

  boot.initrd.availableKernelModules = [ ];

  # hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.wireless-regdb ]; # is this necessary?

  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  services.xserver.videoDrivers = ["i915"];
}