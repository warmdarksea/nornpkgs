{ config, lib, pkgs, modulesPath, ... }:

{
  # machine specs live in hw/dell_xps_13_9310.nix

  boot.initrd.luks.devices.cryptstorage.device =
    config.gensokyo.disks.cryptstorage or "/dev/disk/by-label/sea-cryptstorage";

  fileSystems."/" =
    { device = "torch";
      fsType = "zfs";
    };
    

  fileSystems."/nix" =
    { device = "torch/nix";
      fsType = "zfs";
    };

  fileSystems."/home" =
    { device = "torch/home";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = config.gensokyo.disks.boot or "/dev/disk/by-label/sea-boot";
      fsType = "ext4";
    };

  fileSystems."/boot/efi" =
    { device = config.gensokyo.disks.efi or "/dev/disk/by-label/SEA_EFI";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp0s13f0u1u4.useDHCP = lib.mkDefault true;
  #networking.hostId = "AAAAAAAA";

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking.hostName = "sea";
  networking.hostId = lib.mkDefault "00000000";

  boot.kernelParams = ["zfs.zfs_arc_min=536870912" "zfs.zfs_arc_max=2147483648"];

  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/secret/secureboot";
  };

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.systemd-boot.memtest86.enable = true;

  networking.wireguard.interfaces = {
    wg2 = {
      # remember to open the port for this in allowedUDPPorts
      listenPort = 44283;

      # make sure this is a string, not a file path, or it'll end up in the
      # store
      privateKeyFile = "/var/secret/wg/awsvpn/privkey";

      # we need to set route weights, so do it manually
      allowedIPsAsRoutes = false;

      # ips, peers & routes (VPN-internal addressing, peer public keys,
      # endpoints) live in gensokyo-private.nixosModules.sea
    };
  };

  virtualisation.docker.storageDriver = "zfs";
  virtualisation.docker.daemon.settings = {
    storage-opts = [ "zfs.fsname=torch/docker" ];
  };

  system.stateVersion = "24.11";
}
