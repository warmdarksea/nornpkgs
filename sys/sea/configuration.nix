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

  networking.hostName = "sea";

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
  
  services.fprintd.enable = lib.mkForce false;
  powerManagement.enable = true;
  #services.tlp.enable = true;
  #services.flatpak.enable = true;

  networking.wireguard.interfaces = {
    wg2 = {
      ips = [ "0.0.0.0/24" ];
      # remember to open the port for this in allowedUDPPorts
      listenPort = 44283;

      # make sure this is a string, not a file path, or it'll end up in the
      # store
      privateKeyFile = "/var/secret/wg/awsvpn/privkey";

      # we need to set route weights, so do it manually
      allowedIPsAsRoutes = false;
      postSetup = ''
       ip route add 0.0.0.0/24 dev wg2 metric 200
       ip route add 0.0.0.0/24 dev wg2 via 0.0.0.0 metric 200
      '';

      peers = [
        {
          publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          presharedKeyFile = "/var/secret/wg/awsvpn/psk";

          allowedIPs = [ "0.0.0.0/24" "0.0.0.0/24" ];

          # note: need to do some firewall stuff for handshake to work, see:
          # https://discourse.nixos.org/t/solved-minimal-firewall-setup-for-wireguard-client/7577
          endpoint = "0.0.0.0:44283"; 

          # Send keepalives every 25 seconds. Important to keep NAT tables alive.
          persistentKeepalive = 25;
        }
      ];
    };
  };

  hardware.bluetooth.enable = true;
  hardware.sensor.iio.enable = true;

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts
    nerdfonts
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
    wrapperFeatures.gtk = true; # so that gtk works properly
    extraPackages = with pkgs; [
      swaylock
      swayidle
      wl-clipboard
      mako # notification daemon
      alacritty # Alacritty is the default terminal in the config

      waybar

      #       nwg-menu
      # #      nwg-panel
      #       nwg-drawer
      #       nwg-wrapper
      #       nwg-launchers

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
  # sound.enableOSSEmulation = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
    wireplumber.enable = true;
    systemWide = true;
  };

  virtualisation.lxd.enable = true;
  virtualisation.podman.enable = true;
  virtualisation.docker.storageDriver = "zfs";
  virtualisation.docker = {
    enable = true;

    daemon.settings = {
      storage-opts = [ "zfs.fsname=torch/docker" ];
    };
  };
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      ovmf = {
        enable = true;
        packages = [(pkgs.OVMF.override {
          secureBoot = true;
          tpmSupport = true;
        }).fd];
      };
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

  services.udev.packages = with pkgs; [ gnome.gnome-settings-daemon ];

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

  system.stateVersion = "24.11"; # Did you read the comment?
}
