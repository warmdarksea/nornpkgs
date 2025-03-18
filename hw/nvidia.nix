{ config, lib, options, pkgs, types, ... }:

{
  imports = [ ./gpubase.nix ];
  # breaks gpu in containers
  hardware.nvidia.modesetting.enable = false;

  services.xserver.videoDrivers = ["nvidia"];
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
}