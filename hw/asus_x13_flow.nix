{ config, lib, pkgs, ... }:

# ROG Flow X13 2023 (GV302XV, amd cpu + amdgpu igpu + nvidia dgpu).
# used together with (from nixos-hardware):
#   common-cpu-amd, common-cpu-amd-pstate, common-gpu-amd,
#   common-pc-laptop, common-pc-laptop-ssd
# this used to be a fork of nixos-hardware's asus/x13-flow; the delta is
# inlined here so the input can point at upstream. deliberately does NOT
# force boot.kernelPackages = linuxPackages_latest like the upstream asus
# modules do -- sys/hell pins the lts kernel for zfs.
{
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" "usbhid" "usb_storage" "sd_mod" "sdhci_pci" ];
  boot.kernelModules = [ "kvm-amd" ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;

  services.xserver.videoDrivers = [ "amdgpu" ];

  # AMD has better battery life with PPD over TLP:
  # https://community.frame.work/t/responded-amd-7040-sleep-states/38101/13
  services.power-profiles-daemon.enable = lib.mkDefault true;
}
