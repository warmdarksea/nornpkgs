{ config, lib, pkgs, ... }: {
  imports = [
    # Include the results of the hardware scan.
    #./hardware-configuration.nix
  ];

  nixpkgs.config.allowlistedLicenses = with lib.licenses; [ bsl11 ];

  boot.kernelParams = ["zfs.zfs_arc_min=536870912" "zfs.zfs_arc_max=2147483648"];

  #boot.loader.grub.device = "/dev/sdd";   # (for BIOS systems only)
  #boot.loader.systemd-boot.enable = true; # (for UEFI systems only)

  # Note: setting fileSystems is generally not
  # necessary, since nixos-generate-config figures them out
  # automatically in hardware-configuration.nix.
  #fileSystems."/".device = "/dev/disk/by-label/REDACTED";

  #networking.hostName = "chireiden";

  # Enable the OpenSSH server.
  services.sshd.enable = true;

  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/secret/secureboot";
  };

  # Lanzaboote currently replaces the systemd-boot module.
  # This setting is usually set to true in configuration.nix
  # generated at installation time. So we force it to false
  # for now.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.systemd-boot.memtest86.enable = true;
  #boot.loader.systemd-boot.extraEntries."Windows 11" = ''
  #  title Windows 11
  #  efi /EFI/Microsoft/Boot/bootmgfw.efi
  #'';

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
    wrapperFeatures.gtk = true; # so that gtk works properly
    extraPackages = with pkgs; [
      #       swaylock
      #       swayidle
      #       wl-clipboard
      #       mako # notification daemon
      #       alacritty # Alacritty is the default terminal in the config

      #       waybar

      #       nwg-menu
      # #      nwg-panel
      #       nwg-drawer
      #       nwg-wrapper
      #       nwg-launchers

      #       grim
      #       slurp
      
      #       wlogout
      #       hicolor-icon-theme
    ];
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
  # sound.enableOSSEmulation = true;
  # rtkit + pipewire live in lib/desktop.nix
  services.pipewire.systemWide = true;

  #virtualisation.lxd.enable = true;
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
      # ovmf = {
      #   enable = true;
      #   packages = [(pkgs.OVMF.override {
      #     secureBoot = true;
      #     tpmSupport = true;
      #   }).fd];
      # };
    };
  };

  environment.systemPackages = with pkgs; [
    #      gcc
    #      libsForQt5.bismuth
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

  system.stateVersion = "24.11"; # Did you read the comment?
}
