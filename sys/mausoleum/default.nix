{ config, lib, pkgs, ... }: {
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  services.thermald.enable = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;

    wireplumber.enable = true;
  };

  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  systemd.services."display-manager".enable = false;
  services.xserver.desktopManager.gnome.enable = true;
  programs.dconf.enable = true;

  services.xrdp.enable = true;
  services.xrdp.audio.enable = true;
  services.xrdp.port = 3389;
  services.xrdp.extraConfDirCommands = ''
    substituteInPlace $out/sesman.ini \
      --replace AllowRootLogin=true AllowRootLogin=false \
      --replace RestrictOutboundClipboard=none RestrictOutboundClipboard=all \
      --replace RestrictInboundClipboard=none RestrictInboundClipboard=all
  '';
  services.avahi.enable = false;

  users.users.yoshika = {
    isNormalUser = true;
    extraGroups = ["wheel" "video"];
  };

  environment.systemPackages = with pkgs; [
    vim
    gnumake
    wget
    sbctl
    efibootmgr
    pv
    gtk4
    hydrus
  ];
}
