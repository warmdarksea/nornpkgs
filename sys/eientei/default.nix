{ config, lib, pkgs, ... }: {
  nixpkgs.config.allowUnfree = true;

  # machine specs live in hw/eeepc.nix
  nixpkgs.hostPlatform = "i686-linux";

  networking.networkmanager.enable = true;
  time.timeZone = "America/New_York";

  environment.systemPackages = with pkgs; [
    wget emacs-nox
  ];

  services.openssh.enable = true;

  # 2GB of ram; keep the old sound server, not pipewire
  services.pipewire.enable = false;
  services.pulseaudio.enable = true;

  services.xserver.enable = true;
  services.xserver.exportConfiguration = true;
  services.xserver.xkb.layout = "us";
  services.xserver.windowManager.dwm.enable = true;
  services.xserver.displayManager.lightdm.enable = true;
  services.libinput.enable = true;

  fonts = {
    enableDefaultPackages = false;
    packages = with pkgs; [
      xorg.fontbh100dpi
      xorg.fontmiscmisc
      xorg.fontcursormisc
      ubuntu-classic
      liberation_ttf
      terminus_font
      proggyfonts
      unifont
    ];
    fontconfig = {
      hinting.autohint = false;
      useEmbeddedBitmaps = true;
      defaultFonts.serif = [ "Liberation Serif" "Times New Roman" ];
      defaultFonts.sansSerif = [ "Liberation Sans" "Arial" "Ubuntu" ];
      defaultFonts.monospace = [ "Ubuntu Mono" ];
    };
  };

  users.users.kaguya = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };
}
