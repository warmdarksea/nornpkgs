{ config, lib, pkgs, ... }:

# library: desktop, i7-12700KF + RTX 3090 + mellanox nic
{
  imports = [ ../lib/nvidia_3090_unlock.nix ];

  boot.initrd.availableKernelModules = [ "vmd" "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "mlx5_core" ];
  boot.initrd.kernelModules = [ "kvm-intel" ];

  boot.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
  boot.blacklistedKernelModules = [ "nouveau" ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = true;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    open = true;

    nvidiaSettings = false;

    nvidiaPersistenced = true;
  };

  # full-rate fp16/bf16 on the 3090, set up in the initrd before nvidia
  # (stage 2, boot.kernelModules above) binds the card
  hardware.nvidia-3090-unlock.enable = true;

  # the gpu for containers
  virtualisation.docker.enableNvidia = true;
}
