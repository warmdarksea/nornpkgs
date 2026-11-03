# https://gpd.hk/gpdpocket3firmware

{ config, lib, pkgs, ... }: {
  networking.networkmanager.enable = true;

  services.xserver.enable = true;
  # "iris" is a mesa driver, not an X11 driver; modesetting is the right one
  services.xserver.videoDrivers = ["modesetting"];
  services.xserver.layout = "us";
  services.xserver.displayManager.sddm.enable = true;
  hardware.opengl.driSupport32Bit = true;
  sound.enableOSSEmulation = true;
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
  programs.nm-applet.indicator = true;

  # rtkit + pipewire live in lib/desktop.nix

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      wl-clipboard
      mako # notification daemon
      alacritty

      waybar

      nwg-menu
      nwg-drawer
      nwg-wrapper
      nwg-launchers

      grim
      slurp

      wlogout
      hicolor-icon-theme
    ];
  };
  services.xserver.desktopManager.plasma6.enable = true;

  users.users.nazrin = {
    isNormalUser = true;
    extraGroups = ["wheel"];
  };

  services.openssh.enable = true;

  networking.firewall.enable = true;
}
