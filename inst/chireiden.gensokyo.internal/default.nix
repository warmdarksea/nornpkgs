{ config, lib, pkgs, modulesPath, ... }:

{
  # machine specs live in hw/lenovo_thinkpad_x13_gen2.nix

  boot.initrd.luks.devices.cryptstorage.device =
    config.gensokyo.disks.cryptstorage or "/dev/disk/by-label/chireiden-cryptstorage";

  fileSystems."/" =
    { device = "orbit";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    { device = "orbit/nix";
      fsType = "zfs";
    };

  fileSystems."/home" =
    { device = "orbit/home";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = config.gensokyo.disks.boot or "/dev/disk/by-label/chireiden-boot";
      fsType = "ext4";
    };

  fileSystems."/boot/efi" =
    { device = config.gensokyo.disks.efi or "/dev/disk/by-label/CHIREIDEN_EFI";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.docker0.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp2s0f0.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp2s0f0.mgmt.useDHCP = lib.mkDefault true;
  # networking.interfaces.lxdbr0.useDHCP = lib.mkDefault true;
  # networking.interfaces.veth-wg3b.useDHCP = lib.mkDefault true;
  # networking.interfaces.virbr0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wg0.useDHCP = lib.mkDefault true;
  # networking.interfaces.wg2.useDHCP = lib.mkDefault true;
  # networking.interfaces.wg3.useDHCP = lib.mkDefault true;
  # networking.interfaces.wgbr3.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp3s0.useDHCP = lib.mkDefault true;
  #networking.hostId = "AAAAAAAA";

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking.hostName = "chireiden";
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
      privateKeyFile = "/var/secret/wg/chireiden/privkey";

      # we need to set route weights, so do it manually
      allowedIPsAsRoutes = false;

      # ips, peers & routes (VPN-internal addressing, peer public keys,
      # endpoints) live in gensokyo-private.nixosModules.chireiden
    };
  };

  virtualisation.docker.storageDriver = "zfs";
  virtualisation.docker.daemon.settings = {
    storage-opts = [ "zfs.fsname=orbit/docker" ];
  };

  system.stateVersion = "24.11";
}
