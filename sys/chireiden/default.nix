{ config, lib, pkgs, ... }: {
  nixpkgs.config.allowlistedLicenses = with lib.licenses; [ bsl11 ];

  services.sshd.enable = true;

  # hardware.bluetooth lives in lib/desktop.nix

  gtk.iconCache.enable = true;
  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = [ ];
  };

  programs.wireshark.enable = true;

  services.displayManager.autoLogin = {
    enable = true;
    user = "satori";
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

  users.users.satori = {
    uid = 1000;
    extraGroups = [ "wheel" "video" "sudo" "render" "networkmanager" "docker" "podman" "libvirtd" "wireshark" "lxd" "satori-game" "satori-dev" "input" "plugdev" "pipewire" "lp" "scanner"];
    isNormalUser = true;
  };
}
