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

  nixpkgs.config.allowUnfree = true;

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
}
