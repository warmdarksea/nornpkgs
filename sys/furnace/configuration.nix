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

let
  RFC1918Addresses = [ "0.0.0.0/5" "0.0.0.0/7" "0.0.0.0/8" "0.0.0.0/6" "0.0.0.0/4" "0.0.0.0/3" "0.0.0.0/2" "0.0.0.0/3" "0.0.0.0/5" "0.0.0.0/6" "0.0.0.0/12" "0.0.0.0/11" "0.0.0.0/10" "0.0.0.0/9" "0.0.0.0/8" "0.0.0.0/7" "0.0.0.0/4" "0.0.0.0/9" "0.0.0.0/11" "0.0.0.0/13" "0.0.0.0/16" "0.0.0.0/15" "0.0.0.0/14" "0.0.0.0/12" "0.0.0.0/10" "0.0.0.0/8" "0.0.0.0/7" "0.0.0.0/6" "0.0.0.0/5" "0.0.0.0/4" ];
in rec {
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

  #services.diod = {
  #  enable = true;
  #  listen = [ "0.0.0.0:564" ];

  #  exports = [ "/yet/vid" ];
  #};

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

  networking.firewall.allowedUDPPorts = [
    config.networking.wireguard.interfaces.wg-redacted.listenPort
  ];

  networking.nftables.enable = true;
  networking.iproute2.enable = true;
  
  # this means we don't need reverse-routes for everything in the routing table
  networking.firewall.checkReversePath = "loose";
  networking.firewall.rejectPackets = true;

    # nuclear option, do not use
  #networking.firewall.trustedInterfaces = [ "lxdbr0" "virbr0" ];
  #networking.firewall.extraCommands = ''
  #    iptables -I INPUT -i lxdbr0 -d 0.0.0.0/8,0.0.0.0/12,0.0.0.0/16 -j DROP
  #    iptables -I INPUT -i lxdbr0 -d 0.0.0.0/24 -j ACCEPT
  #  # allow dhcp/dns traffic on lxd bridge
  #  # iptables -A INPUT -i lxdbr0 -p udp --dport 67:68 --sport 67:68 -j ACCEPT
  #  # iptables -A INPUT -i lxdbr0 -p udp --dport 53 --sport 53 -j ACCEPT
  #  # iptables -I INPUT -i lxdbr0 -j ACCEPT
  #'';
  #networking.firewall.extraForwardRules = ''
  #  iifname "lxdbr0" accept
  #  oifname "lxdbr0" accept
  #'';


   networking.iproute2.rttablesExtraConfig = ''
         # 109 rt_redacted
         # 247 rt_redacted
         # 176 rt_redacted
         75 rt_redacted
       '';

  #networking.bridges = {
  # egress: wg1 (redacted redacted)
  # wgbr1 = {
  #   interfaces = [ ]; # gets NAT forwarded to wg1
  # };
  #};

  # systemd.services."wireguard-wg1".after = ["wgbr1-netdev.service"];
  # networking.interfaces.wgbr1 = {
  #   useDHCP = false;
  #   ipv4.addresses = [
  #     {
  #       address = "0.0.0.0";
  #       prefixLength = 24;
  #     }
  #  ];
  # ipv4.routes = [ {options.scope = "link";} ];

   ipv4.routes = [
     {
       address = "0.0.0.0";
       prefixLength = 16;
       options.table = "rt_redacted";
     }
   ];

  networking.wireguard.interfaces = {
    wg-redacted = {
      ips = [ "0.0.0.0/32" ];
      # remember to open the port for this in allowedUDPPorts
      listenPort = 51820;

      # make sure this is a string, not a file path, or it'll end up in the
      # store
      privateKeyFile = "/var/secret/wg/redacted/privkey";

      peers = [
        {
          publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

          # for testing
          #allowedIPs = [ "0.0.0.0/32" ];

          # redacted's DNS server + (all IPs - RFC1918)
          allowedIPs = [ "0.0.0.0/32" ] ++ RFC1918Addresses;

          # note: need to do some firewall stuff for handshake to work, see:
          # https://discourse.nixos.org/t/solved-minimal-firewall-setup-for-wireguard-client/7577
          endpoint = "0.0.0.0:51820";
        }
      ];

      # we need to set route weights, so do it manually
      allowedIPsAsRoutes = false;
      postSetup = ''
        ip route add 0.0.0.0/32 dev wg-redacted
      '';
          #   postSetup = ''
    #     ${pkgs.iproute2}/bin/ip route del 0.0.0.0/24 dev wgbr1 || true
    #     ${pkgs.iproute2}/bin/ip route add 0.0.0.0/24 dev wgbr1 table rt_redacted || true
    #     ${pkgs.iproute2}/bin/ip route add 0.0.0.0/32 dev wg1 table rt_redacted
    #     ${pkgs.iproute2}/bin/ip route add default via 0.0.0.0 dev wg1 table rt_redacted
    #     ${pkgs.iproute2}/bin/ip rule add iif wgbr1 lookup rt_redacted
    #     ${pkgs.iproute2}/bin/ip rule add oif wgbr1 lookup rt_redacted
    #     ${pkgs.iproute2}/bin/ip rule add iif wg1 lookup rt_redacted
    #     ${pkgs.iproute2}/bin/ip rule add oif wg1 lookup rt_redacted
    #     ${pkgs.iptables}/bin/iptables -A FORWARD -i wgbr1 -o wg1 -j ACCEPT
    #     ${pkgs.iptables}/bin/iptables -A FORWARD -o wg1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    #     ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o wg1 -j MASQUERADE
    #   '';
    #   postShutdown = ''
    #     ${pkgs.iproute2}/bin/ip route del 0.0.0.0/32 dev wg1 table rt_redacted || true
    #     ${pkgs.iproute2}/bin/ip route del default via 0.0.0.0 dev wg1 table rt_redacted || true
    #     ${pkgs.iproute2}/bin/ip rule del iif wgbr1 lookup rt_redacted || true
    #     ${pkgs.iproute2}/bin/ip rule del oif wgbr1 lookup rt_redacted || true
    #     ${pkgs.iproute2}/bin/ip rule del iif wg1 lookup rt_redacted || true
    #     ${pkgs.iproute2}/bin/ip rule del oif wg1 lookup rt_redacted || true
    #     ${pkgs.iptables}/bin/iptables -D FORWARD -i wgbr1 -o wg1 -j ACCEPT || true
    #     ${pkgs.iptables}/bin/iptables -D FORWARD -o wg1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || true
    #     ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -o wg1 -j MASQUERADE || true
    #   '';

    };
  };

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

  users.users.rtorrent = {
    uid = 4880;
    group = "rtorrent";
    isSystemUser = true;
  };
  users.groups.rtorrent.gid = users.users.rtorrent.uid;

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
  networking.firewall.allowedTCPPorts = [ 443 9081 ];
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

