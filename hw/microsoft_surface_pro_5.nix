{ config, lib, pkgs, ... }:

# microsoft surface pro 5. currently unused; pair with
# nixos-hardware.nixosModules.microsoft-surface-pro-intel when wiring in.
# (this used to live on the nixos-hardware fork as
# microsoft/surface/surface-pro-5.)
{
  #services.xserver.wacom.package = pkgs.libwacom-surface;

  nixpkgs.overlays = lib.mkDefault [
    (self: super: {
      libwacom = super.libwacom-surface;
    })
  ];
}
