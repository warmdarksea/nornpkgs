{ config, lib, pkgs, ... }:

# Dell XPS 13 9310 2-in-1 (tiger lake). used together with
# nixos-hardware.nixosModules.dell-xps-13-9310; this is just the machine
# scan.
{
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "uas" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # 2-in-1: accelerometer for rotation; the fingerprint reader is not worth it
  hardware.sensor.iio.enable = true;
  services.fprintd.enable = lib.mkForce false;
}
