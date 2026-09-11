{ config, lib, pkgs, ... }: {
  imports = [
  ];

  nixpkgs.config.allowUnfreePredicate = pkg: (builtins.elem (lib.getName pkg) [
    "corefonts"
    "nvidia-x11"
    "nvidia-persistenced"
    "nvidia-settings"
    "cudnn"
    #    "cuda_cudart"
    #    "cuda_cccl"
    #    "libcublas"
    #    "nvtop"
    "vcv-rack"
  ]) || (builtins.all (license:
    license.free || builtins.elem license.shortName [
      "CUDA EULA"
      #    "cuDNN EULA"
      #    "cuTENSOR EULA"
      "NVidia OptiX EULA"
    ]
  ) (if builtins.isList pkg.meta.license then pkg.meta.license else [ pkg.meta.license ]));

  nix.settings.keep-failed = true;
  nixpkgs.config.allowUnfree = true;

  # Lanzaboote currently replaces the systemd-boot module.
  # This setting is usually set to true in configuration.nix
  # generated at installation time. So we force it to false
  # for now.
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  boot.loader.efi.canTouchEfiVariables = true;

  # machine specs live in hw/library.nix

  boot.zfs.requestEncryptionCredentials = false;

  fileSystems."/" =
    { device = "story";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    { device = "story/nix";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = config.gensokyo.disks.boot or "/dev/disk/by-partlabel/library-boot";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;  # different port so your normal known_hosts entry doesn't conflict
      hostKeys = [ /var/secret/ssh_library_ed25519_key ];
      authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted" ];
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted"
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  swapDevices = [ ];
  
  networking.useDHCP = lib.mkDefault true;
  #networking.dhcpcd.enable = false;
  #networking.interfaces.enp6s0.ipv4.addresses = [
  #  { address = "0.0.0.0"; prefixLength = 24; }
  #];
  #networking.defaultGateway = "0.0.0.0";
  #networking.nameservers = ["0.0.0.0"];

  virtualisation.docker = {
    enable = true;
    enableNvidia = true;

    # overlayfs backed by zfs is broken, you need to use zfs proper for it to work
    storageDriver = "zfs";
    daemon.settings = {
      storage-opts = [ "zfs.fsname=story/docker" ];
    };
  };

  users.users.patchouli = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
  };

  environment.systemPackages = with pkgs; [
    dtach
    efibootmgr
    sbctl
  ];

  #system.copySystemConfiguration = true;

  #system.stateVersion = "23.05"; # Did you read the comment?
  system.stateVersion = "26.11"; # Did you read the comment?
}
