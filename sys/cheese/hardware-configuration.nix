{ config, lib, pkgs, modulesPath, ... }:

{
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "splice";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    { device = "splice/nix";
      fsType = "zfs";
    };

  fileSystems."/home" =
    { device = "splice/home";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = config.gensokyo.disks.boot or "/dev/disk/by-label/cheese-boot";
      fsType = "ext4";
    };

  fileSystems."/boot/EFI" =
    { device = config.gensokyo.disks.efi or "/dev/disk/by-label/CHEESE_EFI";
      fsType = "vfat";
    };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp0s20f0u1u4.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp175s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp174s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;


  # Use the systemd-boot EFI boot loader.
  #boot.loader.systemd-boot.enable = true;
  #boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/EFI";
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.device = "nodev";

  #boot.loader.grub.gfxpayloadEfi = "keep";
  #boot.loader.grub.gfxmodeEfi = "1200x1920";

  # boot.zfs.enableUnstable = false;
  #boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = ["boot.shell_on_fail"];

  boot.initrd.secrets = {"/splice.h" = /boot/splice.h;};

  boot.initrd.luks.devices = {
    crypted = {
      device = config.gensokyo.disks.crypted or "/dev/disk/by-label/cheese-crypted";
      header = "/splice.h";
      preLVM = true;
    };
  };
}