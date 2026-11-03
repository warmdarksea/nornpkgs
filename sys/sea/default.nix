{ config, lib, pkgs, ... }: {
  nixpkgs.config.allowlistedLicenses = with lib.licenses; [ bsl11 ];

  services.sshd.enable = true;

  powerManagement.enable = true;

  # hardware.bluetooth lives in lib/desktop.nix

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts
    # nerdfonts split into per-font packages (nerd-fonts.*); pick one if wanted
  ];

  gtk.iconCache.enable = true;
  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

  # fixes file conflict with some portal-related file
  xdg.portal.extraPortals = lib.mkForce [ pkgs.xdg-desktop-portal-gtk pkgs.xdg-desktop-portal-wlr ];
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

      dmenu

      grim
      slurp
      
      wlogout
    ];
  };
  services.gnome.gnome-keyring.enable = true;
  security.pam.loginLimits = [
    { domain = "@users"; item = "rtprio"; type = "-"; value = 1; }
  ];

  programs.wireshark.enable = true;

  services.displayManager.autoLogin = {
    enable = true;
    user = "seija";
  };

  # workaround for https://nixos.wiki/wiki/GNOME#automatic_login
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  hardware.pulseaudio.enable = false;
  # rtkit + pipewire live in lib/desktop.nix
  services.pipewire.systemWide = true;

  virtualisation.podman.enable = true;
  # the zfs storage driver and its dataset live in inst/
  virtualisation.docker.enable = true;
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      # the virtualisation.libvirtd.qemu.ovmf submodule was removed from
      # nixpkgs; all OVMF images distributed with QEMU are available by default
    };
  };

  environment.systemPackages = with pkgs; [
    hicolor-icon-theme
    adwaita-icon-theme
    podman
    podman-compose
    gnomeExtensions.workspace-matrix
    gnomeExtensions.appindicator
    gnome-terminal
    efibootmgr
    sbctl
    dislocker
    ntfs3g
  ];

  services.udev.packages = with pkgs; [ gnome-settings-daemon ];

  users.users.seija = {
    uid = 1000;
    extraGroups = [ "wheel" "video" "sudo" "render" "networkmanager" "docker" "podman" "libvirtd" "wireshark" "lxd" "satori-game" "satori-dev" "input" "plugdev" "pipewire" "lp" "scanner"];
    isNormalUser = true;
  };

  users.users.flandre = {
    uid = 1001;
    extraGroups = [ "video" "render" "input" "plugdev" "pipewire" ];
    isNormalUser = true;
  };
}
