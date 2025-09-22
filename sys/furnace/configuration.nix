# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# todo:
# webdav
# komga
# jellyfin
# generic 9p access
# tailscale

{ config, lib, pkgs, ... }:

rec {
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "furnace"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  
  networking.useDHCP = lib.mkDefault true;
  #networking.networkmanager.enable = true;

  services.diod = {
    enable = true;
    listen = [ "0.0.0.0:564" ];

    exports = [ "/yet/vid" ];
  };

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "0.0.0.0,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  
  
  virtualisation.docker = {
    enable = true;

    #enableNvidia = true;
    storageDriver = "zfs";
    daemon.settings = {
      storage-opts = [ "zfs.fsname=fern/docker" ];
    };
  };
  virtualisation.podman = {
    enable = true;
    #enableNvidia = true;
    extraPackages = with pkgs; [
      dive
      podman-compose
      podman-tui
    ];
  };

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  # services.pipewire = {
  #   enable = true;
  #   pulse.enable = true;
  # };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.rin = {
    uid = 5549;

    subUidRanges = [
      { startUid = 100000; count = 16777216; }
      { startUid = users.users.www-jellyfin.uid; count = 1; }
      { startUid = users.users.www-komga.uid; count = 1; }
      { startUid = users.users.www-webdav.uid; count = 1; }
      { startUid = users.users.www-nextcloud.uid; count = 1; }
    ];
    subGidRanges = [
      { startGid = 100000; count = 16777216; }
      { startGid = users.groups.www-jellyfin.gid; count = 1; }
      { startGid = users.groups.www-komga.gid; count = 1; }
      { startGid = users.groups.www-webdav.gid; count = 1; }
      { startGid = users.groups.www-nextcloud.gid; count = 1; }
    ];

    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "podman" ]; # Enable ‘sudo’ for the user.
    #   packages = with pkgs; [
    #     tree
    #   ];
  };

  users.users.www-jellyfin = {
    uid = 1536;
    group = "www-jellyfin";
    isSystemUser = true;
  };
  users.groups.www-jellyfin.gid = users.users.www-jellyfin.uid;

  users.users.www-komga = {
    uid = 8209;
    group = "www-komga";
    isSystemUser = true;
  };
  users.groups.www-komga.gid = users.users.www-komga.uid;

  users.users.www-webdav = {
    uid = 9031;
    group = "www-webdav";
    isSystemUser = true;
  };
  users.groups.www-webdav.gid = users.users.www-webdav.uid;

  users.users.www-nextcloud = {
    uid = 3568;
    group = "www-nextcloud";
    isSystemUser = true;
  };
  users.groups.www-nextcloud.gid = users.users.www-nextcloud.uid;

  # programs.firefox.enable = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    #   wget
    sbctl
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 443 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?

}

