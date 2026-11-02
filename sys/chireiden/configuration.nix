{ config, lib, pkgs, ... }: {
  nixpkgs.config.allowlistedLicenses = with lib.licenses; [ bsl11 ];

  boot.kernelParams = ["zfs.zfs_arc_min=536870912" "zfs.zfs_arc_max=2147483648"];

  services.sshd.enable = true;

  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/secret/secureboot";
  };

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.systemd-boot.memtest86.enable = true;

  networking.wireguard.interfaces = {
    wg2 = {
      # remember to open the port for this in allowedUDPPorts
      listenPort = 44283;

      # make sure this is a string, not a file path, or it'll end up in the
      # store
      privateKeyFile = "/var/secret/wg/chireiden/privkey";

      # we need to set route weights, so do it manually
      allowedIPsAsRoutes = false;

      # ips, peers & routes (VPN-internal addressing, peer public keys,
      # endpoints) live in gensokyo-private.nixosModules.chireiden
    };
  };

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
  virtualisation.docker.storageDriver = "zfs";
  virtualisation.docker = {
    enable = true;

    daemon.settings = {
      storage-opts = [ "zfs.fsname=orbit/docker" ];
    };
  };
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

  system.stateVersion = "24.11";
}
