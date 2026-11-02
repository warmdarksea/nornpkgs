{ config, lib, pkgs, ... }: {
  nixpkgs.config.allowUnfreePredicate = pkg: (builtins.elem (lib.getName pkg) [
    "corefonts"
    "nvidia-x11"
    "nvidia-persistenced"
    "nvidia-settings"
    "cudnn"
    "vcv-rack"
  ]) || (builtins.all (license:
    license.free || builtins.elem license.shortName [
      "CUDA EULA"
      "NVidia OptiX EULA"
    ]
  ) (if builtins.isList pkg.meta.license then pkg.meta.license else [ pkg.meta.license ]));

  nix.settings.keep-failed = true;

  boot.loader.efi.efiSysMountPoint = "/boot/EFI";
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.device = "nodev";

  boot.initrd.kernelModules = [ ];
  boot.extraModulePackages = [ ];

    fileSystems."/" =
    { device = "story";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    { device = "story/nix";
      fsType = "zfs";
    };

  swapDevices = [ ];

  nixpkgs.config.allowUnfree = true;

  networking.useDHCP = lib.mkDefault true;

  users.users.marisa = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
  };

  environment.systemPackages = with pkgs; [
    cudatoolkit
    docker
    docker-compose
    dtach
  ];

  system.stateVersion = "23.05"; # Did you read the comment?
}
