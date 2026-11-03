{ config, lib, pkgs, modulesPath, ... }:

{
  # machine specs live in hw/lattepanda_v1.nix

  fileSystems."/" =
    { device = "/dev/mapper/fright0";
      fsType = "ext4";
    };

  boot.initrd.luks.devices."fright0" = {
    device = config.gensokyo.disks.fright0 or "/dev/disk/by-label/abandonedfactory-fright0";
    crypttabExtraOpts = [ "tpm2-device=auto" ];
  };

  fileSystems."/boot" =
    { device = config.gensokyo.disks.boot or "/dev/disk/by-label/AF_BOOT";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking.hostName = "abandonedfactory";

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  system.stateVersion = "23.11";
}
