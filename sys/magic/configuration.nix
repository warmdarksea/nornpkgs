{ config, lib, pkgs, ... }: {
  imports = [
  ];

  boot.loader.efi.efiSysMountPoint = "/boot/EFI";
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.device = "nodev";

  boot.initrd.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  boot.initrd.secrets = {
    "/alloy.h" = /boot/alloy.h;
  };

  boot.initrd.luks.devices = {
    crypted = {
      device = "/dev/disk/by-id/REDACTED";
      header = "/alloy.h";
      preLVM = true;
    };
  };

  fileSystems."/" =
    { device = "alloy";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/REDACTED";
      fsType = "ext4";
    };

  fileSystems."/boot/EFI" =
    { device = "/dev/disk/by-uuid/REDACTED";
      fsType = "vfat";
    };

  fileSystems."/home" =
    { device = "alloy/home";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    { device = "alloy/nix";
      fsType = "zfs";
    };

  #     fileSystems."/mnt/oft" =
  #       { device = "oft";
  #         fsType = "zfs";
  #         options = ["defaults" "nofail"];
  #       };
  # #    systemd.services."zfs-import-oft.service".wants = ["decrypt-external-disks.service"];
  # #    systemd.services."zfs-import-oft.service".serviceConfig.TimeoutStartUSec = "10s";
  
  #     fileSystems."/mnt/orient" =
  #       { device = "orient";
  #         fsType = "zfs";
  #         options = ["defaults" "nofail"];
  #       };
  # #    systemd.services."zfs-import-orient.service".wants =  ["decrypt-external-disks.service"];
  # #    systemd.services."zfs-import-orient.service".serviceConfig.TimeoutStartUSec = "10s";

  #     systemd.services.decrypt-external-disks = {
  #       script = ''
  #         ${pkgs.cryptsetup}/bin/cryptsetup luksOpen --header /var/luks/oft.h -d /var/luks/oft.k /dev/disk/by-id/REDACTED oft0
  #         ${pkgs.cryptsetup}/bin/cryptsetup luksOpen --header /var/luks/orient.h -d /var/luks/orient.k /dev/disk/by-id/REDACTED orient0
  #       '';
  #       after = [ "-.mount" ];
  #       before = ["zfs-import-oft.service" "zfs-import-orient.service"];
  #       wantedBy = [ "local-fs.target" ];
  #     };

  swapDevices = [ ];

  nixpkgs.config.allowUnfree = true;

  networking.hostName = "magic";
  networking.hostId = "AAAAAAAA";
  networking.dhcpcd.enable = false;
  networking.interfaces.enp6s0.ipv4.addresses = [
    { address = "0.0.0.0"; prefixLength = 24; }
  ];
  networking.defaultGateway = "0.0.0.0";
  networking.nameservers = ["0.0.0.0"];

  virtualisation.docker = {
    enable = true;
    enableNvidia = true;

    # overlayfs backed by zfs is broken, you need to use zfs proper for it to work
    storageDriver = "zfs";
    daemon.settings = {
      storage-opts = [ "zfs.fsname=alloy/docker" ];
    };
  };

  users.users.marisa = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
  };

  environment.systemPackages = with pkgs; [
    cudatoolkit
    docker
    docker-compose
  ];

  #system.copySystemConfiguration = true;

  system.stateVersion = "23.05"; # Did you read the comment?
}