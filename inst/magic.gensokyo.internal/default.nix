{ config, lib, pkgs, ... }: {
  networking.hostName = "magic";
  networking.hostId = lib.mkDefault "00000000";

  boot.loader.efi.efiSysMountPoint = "/boot/EFI";
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.device = "nodev";

  fileSystems."/" =
    { device = "story";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    { device = "story/nix";
      fsType = "zfs";
    };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  system.stateVersion = "23.05";
}
