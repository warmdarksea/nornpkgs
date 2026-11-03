# todo:
# webdav
# komga
# jellyfin
# generic 9p access
# tailscale

{ config, lib, pkgs, ... }:

rec {
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
    journaldAccess = true;
    
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
        type = "file";
        inputs = ["receive"];
        path = "/srv/log/vector/%Y-%m-%d-{{ source_ip }}.log";
        encoding.codec = "json";
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
    extraGroups = [ "wheel" "docker" "podman" ];
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

  environment.systemPackages = with pkgs; [
    vim
    sbctl
  ];

  networking.firewall.allowedTCPPorts = [ 443 9081 ];

  system.stateVersion = "25.11";

}

