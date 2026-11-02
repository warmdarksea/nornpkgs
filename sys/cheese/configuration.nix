# https://gpd.hk/gpdpocket3firmware

{ config, lib, pkgs, ... }: {
  i18n = {
    consoleFont = "latarcyrheb-sun32";
  };

  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Enable the X11 windowing system.
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
    wrapperFeatures.gtk = true; # so that gtk works properly
    extraPackages = with pkgs; [
      swaylock
      swayidle
      wl-clipboard
      mako # notification daemon
      alacritty # Alacritty is the default terminal in the config

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

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Or disable the firewall altogether.
  networking.firewall.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It’s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
