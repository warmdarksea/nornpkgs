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

  networking.useDHCP = lib.mkDefault true;

  networking.nftables.enable = true;
  networking.iproute2.enable = true;
  
  # this means we don't need reverse-routes for everything in the routing table
  networking.firewall.checkReversePath = "loose";
  networking.firewall.rejectPackets = true;

  services.vector = {
    enable = true;
    journaldAccess = true;  # Gives Vector permission to read journald
    
    settings = {
      sources.receive = {
        type = "http_server";
        address = "0.0.0.0:9081";
      };

      sources.journald = {
        type = "journald";
        current_boot_only = false;
      };

      sinks.local = {
        type = "file";
        inputs = ["journald"];
        path = "/srv/log/vector/%Y-%m-%d-localhost.log";
        encoding.codec = "json";
      };
      
      sinks.remote = {
        type = "file";  # or "socket" to send to another Vector instance
        inputs = ["receive"];
        path = "/srv/log/vector/%Y-%m-%d-{{ source_ip }}.log";
        encoding.codec = "json";  # structured data in text files
      };
    };
  };
  
  virtualisation.docker = {
    enable = true;

    storageDriver = "zfs";
    daemon.settings = {
      storage-opts = [ "zfs.fsname=fern/docker" ];
    };
  };
  virtualisation.podman = {
    enable = true;
    extraPackages = with pkgs; [
      dive
      podman-compose
      podman-tui
    ];
  };

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

  users.users.rtorrent = {
    uid = 4880;
    group = "rtorrent";
    isSystemUser = true;
  };
  users.groups.rtorrent.gid = users.users.rtorrent.uid;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    sbctl
  ];

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 443 9081 ];

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

