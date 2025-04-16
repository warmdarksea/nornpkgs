{ config, lib, pkgs, ... }: {
  imports = [
    # Include the results of the hardware scan.
    #./hardware-configuration.nix
  ];

  nixpkgs.config.cudaSupport = true;
  
  nixpkgs.config.allowUnfreePredicate = pkg: (builtins.elem (lib.getName pkg) [
    "corefonts"
    "nvidia-x11"
    "nvidia-persistenced"
    "nvidia-settings"
    #    "cuda_cudart"
    #    "cuda_cccl"
    #    "libcublas"
    #    "nvtop"
    "vcv-rack"
  ]) || (builtins.all (license:
  license.free || builtins.elem license.shortName [
    "CUDA EULA"
    #    "cuDNN EULA"
    #    "cuTENSOR EULA"
    "NVidia OptiX EULA"
  ]
  ) (if builtins.isList pkg.meta.license then pkg.meta.license else [ pkg.meta.license ]));

  boot.kernelParams = [ "zfs.zfs_arc_min=536870912" "zfs.zfs_arc_max=2147483648" "cgroup_enable=memory" "systemd.unified_cgroup_hierarchy=1" ];
  # "vm.min_free_kbytes=524288"
  boot.kernel.sysctl = {
    "vm.min_free_kbytes" = 524288;
  };

  #boot.loader.grub.device = "/dev/sdd";   # (for BIOS systems only)
  #boot.loader.systemd-boot.enable = true; # (for UEFI systems only)
  #boot.kernelPackages = pkgs.linuxPackages_6_13;
  #boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  #boot.kernelPackages = pkgs.linuxPackages_latest;
  # at the time of writing, this is equal to zfs_unstable
  # boot.zfs.package = pkgs.zfs;

  nixpkgs.overlays = [
  (self: super: {
    linuxPackages_6_14 = super.linuxPackages_6_14.extend (lpself: lpsuper: {
      zfs_unstable = lpsuper.zfs_unstable.overrideAttrs (oldAttrs: {
        meta = oldAttrs.meta // { broken = true; }; # remove whenever you feel like it
      });
    });
    my_zfs = super.zfs_unstable.overrideAttrs(old: {
      kernelCompatible = true;
      #meta.broken = false;
      rev = "301da593ade391fa78a660c7b42325cd2ace593a";
    });
  })
];


  specialisation = {
    lts.configuration = {
      boot.kernelPackages = pkgs.linuxPackages_6_12;
      system.nixos.tags = [ "lts-kernel" ];
      #nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        #  "nvidia-x11"
        #];
        #boot.zfs.package = pkgs.zfs;
    };
    
    stable.configuration = {
      boot.kernelPackages = pkgs.linuxPackages_6_13;
      system.nixos.tags = [ "stable-kernel" ];
      #nixpkgs.config = licenseConfig;
      #boot.zfs.package = pkgs.zfs;
    };

    #latest.nixpkgs.config.allowBroken = true;
    # latest.configuration = {
    #   boot.kernelPackages = pkgs.linuxPackages_6_14;
    #   #boot.extraModulePackages = [
    #   #  (pkgs.linuxPackages_latest.zfs_unstable.overrideAttrs(old: {
    #   #    meta = (old.meta or {}) // { broken = false; };
    #   #  }))
    #   #];
    #   system.nixos.tags = [ "latest-kernel" ];
    #   boot.zfs.package = pkgs.my_zfs;
      #boot.zfs.package = pkgs.zfs;
      #nixpkgs.config = licenseConfig;
      # nixpkgs options are global, so can't set per specialization
      # nixpkgs.config.allowBroken = true;
      #nixpkgs.overlays = [
      #  (final: prev: {
      #    linuxPackages_latest.zfs_unstable = prev.linuxPackages_latest.zfs_unstable.overrideAttrs(old: {
      #    meta = (old.meta or {}) // { broken = false; };
      #    });
      #  })
      #];
    #   nixpkgs.overlays = (config.nixpkgs.overlays or []) ++ [
    #   (final: prev: {
    #     # Target the specific ZFS kernel module
    #     #linuxPackages_latest = prev.linuxPackages_latest.extend (lpFinal: lpPrev: {
    #     #  zfs_unstable = lpPrev.zfs_unstable.overrideAttrs (old: {
    #     #    meta = (old.meta or {}) // { broken = false; };
    #     #  });
    #     #});
    #     linuxKernel.packages.linux_6_14.zfs_unstable = prev.linuxKernel.packages.linux_latest.zfs_unstable.overrideAttrs (old: {
    #       meta = (old.meta or {}) // { broken = false; };
    #     });
        
    #     # Also unmark the general package as broken
    #     zfs = prev.zfs.overrideAttrs (old: {
    #       meta = (old.meta or {}) // { broken = false; };
    #     });
    #     zfs_unstable = prev.zfs_unstable.overrideAttrs (old: {
    #       meta = (old.meta or {}) // { broken = false; };
    #     });
    #   })
    # ];
    #};
  };

  # Note: setting fileSystems is generally not
  # necessary, since nixos-generate-config figures them out
  # automatically in hardware-configuration.nix.
  #fileSystems."/".device = "/dev/disk/by-label/REDACTED";

  networking.hostName = "hell";

  services.resolved.llmnr = "false";

  # Enable the OpenSSH server.
  services.sshd.enable = true;

  services.guix.enable = true;

  #boot.loader.efi.efiSysMountPoint = "/boot/efi";

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

  services.printing = {
    enable = true;
    drivers = [pkgs.hplip pkgs.brlaser];
  };
  
  programs.adb.enable = true;
  #services.fprintd.enable = lib.mkForce false;
  powerManagement.enable = true;
  #services.tlp.enable = true;
  services.flatpak.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" "cgroups" ];
  nix.settings.use-cgroups = true;

  # Disable swap for the root slice (all other processes)
  # systemd-run --slice=swap-allowed.slice --scope -p "MemorySwapMax=infinity" your-command
  systemd.slices."-.slice" = {
    description = "Root slice";
    sliceConfig = {
      MemorySwapMax = "0"; # Completely disable swap
    };
  };
  systemd.slices."swap-allowed" = {
    description = "Slice for processes that can use swap";
    sliceConfig = {
      MemorySwapMax = "infinity"; # Allow unlimited swap
    };
  };

  #   32 GB
  # - 2  GB (VRAM)
  # - 18 GB (build)
  # - 6  GB (browser)
  # -------
  #   6  GB (rest)
  systemd.services.nix-daemon.serviceConfig = {
    Nice = 19;

    # reserve core 0
    AllowedCPUs = "1-15";
    #CPUShares = "512";
    CPUWeight = 50;         # Lower than default (100)
    #CPUSchedulingPolicy = "idle";

    MemoryHigh = "14G";
    MemoryMax = "18G";

    IOWeight = 50;          # Lower than default (100)
    #IOSchedulingClass = "idle";

    Slice = "swap-allowed.slice";
  };
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  #hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable_open;

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead 
    # of just the bare essentials.
    powerManagement.enable = true;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = true;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of 
    # supported GPUs is at: 
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus 
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = true;

    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  services.xserver.videoDrivers = lib.mkForce [ "amdgpu" "nvidia" ];

  #boot.extraModulePackages = with pkgs; [ linuxKernel.packages.nvidia_x11 ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ nvidia_x11_beta_open ];
  boot.blacklistedKernelModules = [ "nouveau" ];

  hardware.nvidia.prime = {
    offload = {
      enable = true;
      enableOffloadCmd = true;
    };
    # Make sure to use the correct Bus ID values for your system!
    amdgpuBusId = "PCI:1:0:0"; # For AMD GPU
    #intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:105:0:0";
  };

  # some networking notes
  # we will want to use the wgN device with one or possibly multiple network namespaces, but it can only be in one at a time. so instead we keep it in the default namespace and create a bridge, and make veth pairs for each additional network namespace we want to use.
  # we also may not want to have any routing table rules in the default network namespace, because the interface may be for testing or other weird stuff. instead, we... wait, what do we do? it looks like we create a new routing table with the weird "multiple routing table" thingie, in the default netns. why do we need that... can't we just have the routing table in the namespace with the veth pair? what routing even happens in the default network namespace? in fact, i kind of specifically want there to not be any routing for wgN in the default netns, it will conflict with at least one other wgN (for the DNS server)
  
  #networking.firewall.allowedUDPPorts = [44283];
  #networking.firewall.allowedUDPPortRanges = [
    #  { from = 60000; to = 61000; }
    #];

    services.tailscale.enable = true;

    # nuclear option, do not use
    networking.firewall.trustedInterfaces = [ "lxdbr0" "virbr0" ];
    networking.firewall.extraCommands = ''
      iptables -I INPUT -i lxdbr0 -d 0.0.0.0/8,0.0.0.0/12,0.0.0.0/16 -j DROP
      iptables -I INPUT -i lxdbr0 -d 0.0.0.0/24 -j ACCEPT
      #  # allow dhcp/dns traffic on lxd bridge
      #  # iptables -A INPUT -i lxdbr0 -p udp --dport 67:68 --sport 67:68 -j ACCEPT
      #  # iptables -A INPUT -i lxdbr0 -p udp --dport 53 --sport 53 -j ACCEPT
      #  # iptables -I INPUT -i lxdbr0 -j ACCEPT
      #'';
      #networking.firewall.extraForwardRules = ''
      #  iifname "lxdbr0" accept
      #  oifname "lxdbr0" accept
      #'';

      networking.iproute2.enable = true;
      
      # this means we don't need reverse-routes for everything in the routing table
      networking.firewall.checkReversePath = "loose";
      networking.firewall.rejectPackets = true;

      networking.iproute2.rttablesExtraConfig = ''
        # 109 rt_redacted
        # 247 rt_redacted
      '';

      networking.bridges = {
        # egress: wg1 (redacted redacted)
        # wgbr1 = {
          #   interfaces = [ ]; # gets NAT forwarded to wg1
          # };
      };

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
            #ipv4.routes = [
              #  {
                #    address = "0.0.0.0";
                #    prefixLength = 24;
                #    options.table = "rt_redacted";
                #  }
                #];
                # };

                networking.wireguard.interfaces = {

                  # higan
                  wg0 = {
                    ips = [ "0.0.0.0/24" ];
                    # remember to open the port for this in allowedUDPPorts
                    listenPort = 44283;

                    # make sure this is a string, not a file path, or it'll end up in the
                    # store
                    privateKeyFile = "/var/secret/wg/higan/privkey";

                    # we need to set route weights, so do it manually
                    allowedIPsAsRoutes = false;
                    postSetup = ''
                      ip route add 0.0.0.0/24 dev wg0 metric 200
                      ip route add 0.0.0.0/24 dev wg0 via 0.0.0.0 metric 200
                    '';

                    peers = [
                      {
                        publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                        presharedKeyFile = "/var/secret/wg/higan/psk";

                        allowedIPs = [ "0.0.0.0/24" "0.0.0.0/24" ];

                        # note: need to do some firewall stuff for handshake to work, see:
                        # https://discourse.nixos.org/t/solved-minimal-firewall-setup-for-wireguard-client/7577
                        endpoint = "0.0.0.0:44283"; 

                        # Send keepalives every 25 seconds. Important to keep NAT tables alive.
                        persistentKeepalive = 25;
                      }
                    ];
                  };

                  # redacted redacted (test1)
                  # to test: ip route add 0.0.0.0/32 dev wg1 (then resolve something with it obv)
                  # then ip route del 0.0.0.0/32 dev wg1
                  # wg1 = {
                    #   ips = [ "0.0.0.0/32" "::1/128" ];
                    #   # remember to open the port for this in allowedUDPPorts
                    #   listenPort = 31305;

                    #   # make sure this is a string, not a file path, or it'll end up in the
                    #   # store
                    #   privateKeyFile = "/var/secret/wg/redacted/privkey";

                    #   # we need to set route weights, so do it manually
                    #   allowedIPsAsRoutes = false;
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
                    
                    #   #   ${pkgs.iproute2}/bin/ip route add 0.0.0.0/32 dev wg3 table rt_redacted
                    #   #   ${pkgs.iproute2}/bin/ip route add default via 0.0.0.0 dev wg3 table rt_redacted
                    #   #   ${pkgs.iproute2}/bin/ip rule add iif wgbr3 lookup rt_redacted
                    #   #   ${pkgs.iproute2}/bin/ip rule add oif wgbr3 lookup rt_redacted
                    #   #   ${pkgs.iproute2}/bin/ip rule add iif wg3 lookup rt_redacted
                    #   #   ${pkgs.iproute2}/bin/ip rule add oif wg3 lookup rt_redacted
                    #   #   ${pkgs.iptables}/bin/iptables -A FORWARD -i wgbr3 -o wg3 -j ACCEPT
                    #   #   ${pkgs.iptables}/bin/iptables -A FORWARD -o wg3 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
                    #   #   ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o wg3 -j MASQUERADE
                    #   # '';
                    #   # postShutdown = ''
                    #   #   ${pkgs.iproute2}/bin/ip route del 0.0.0.0/32 dev wg3 table rt_redacted
                    #   #   ${pkgs.iproute2}/bin/ip route del default via 0.0.0.0 dev wg3 table rt_redacted
                    #   #   ${pkgs.iproute2}/bin/ip rule del iif wgbr3 lookup rt_redacted
                    #   #   ${pkgs.iproute2}/bin/ip rule del oif wgbr3 lookup rt_redacted
                    #   #   ${pkgs.iproute2}/bin/ip rule del iif wg3 lookup rt_redacted
                    #   #   ${pkgs.iproute2}/bin/ip rule del oif wg3 lookup rt_redacted
                    #   #   ${pkgs.iptables}/bin/iptables -D FORWARD -i wgbr3 -o wg3 -j ACCEPT
                    #   #   ${pkgs.iptables}/bin/iptables -D FORWARD -o wg3 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
                    #   #   ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -o wg3 -j MASQUERADE
                    #   #   '';

                    #   peers = [
                      #     {
                        #       publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

                        #       # redacted's DNS server + (all IPs - RFC1918)
                        #       #allowedIPs = [ "0.0.0.0/32" ];
                        #       allowedIPs = [ "0.0.0.0/32" "0.0.0.0/5" "0.0.0.0/7" "0.0.0.0/8" "0.0.0.0/6" "0.0.0.0/4" "0.0.0.0/3" "0.0.0.0/2" "0.0.0.0/3" "0.0.0.0/5" "0.0.0.0/6" "0.0.0.0/12" "0.0.0.0/11" "0.0.0.0/10" "0.0.0.0/9" "0.0.0.0/8" "0.0.0.0/7" "0.0.0.0/4" "0.0.0.0/9" "0.0.0.0/11" "0.0.0.0/13" "0.0.0.0/16" "0.0.0.0/15" "0.0.0.0/14" "0.0.0.0/12" "0.0.0.0/10" "0.0.0.0/8" "0.0.0.0/7" "0.0.0.0/6" "0.0.0.0/5" "0.0.0.0/4" ];

                        #       # note: need to do some firewall stuff for handshake to work, see:
                        #       # https://discourse.nixos.org/t/solved-minimal-firewall-setup-for-wireguard-client/7577
                        #       endpoint = "0.0.0.0:3226";
                        #     }
                        #   ];
                        # };

                        # redacted redacted (?? not sure what to use this for)
                        # wg2 = {
                          #   ips = [ "0.0.0.0/32" "::1/128" ];
                          #   # remember to open the port for this in allowedUDPPorts
                          #   listenPort = 31305;

                          #   # make sure this is a string, not a file path, or it'll end up in the
                          #   # store
                          #   privateKeyFile = "/var/secret/wg/redacted/privkey";

                          #   # we need to set route weights, so do it manually
                          #   allowedIPsAsRoutes = false;
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
                          
                          #   #   ${pkgs.iproute2}/bin/ip route add 0.0.0.0/32 dev wg3 table rt_redacted
                          #   #   ${pkgs.iproute2}/bin/ip route add default via 0.0.0.0 dev wg3 table rt_redacted
                          #   #   ${pkgs.iproute2}/bin/ip rule add iif wgbr3 lookup rt_redacted
                          #   #   ${pkgs.iproute2}/bin/ip rule add oif wgbr3 lookup rt_redacted
                          #   #   ${pkgs.iproute2}/bin/ip rule add iif wg3 lookup rt_redacted
                          #   #   ${pkgs.iproute2}/bin/ip rule add oif wg3 lookup rt_redacted
                          #   #   ${pkgs.iptables}/bin/iptables -A FORWARD -i wgbr3 -o wg3 -j ACCEPT
                          #   #   ${pkgs.iptables}/bin/iptables -A FORWARD -o wg3 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
                          #   #   ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o wg3 -j MASQUERADE
                          #   # '';
                          #   # postShutdown = ''
                          #   #   ${pkgs.iproute2}/bin/ip route del 0.0.0.0/32 dev wg3 table rt_redacted
                          #   #   ${pkgs.iproute2}/bin/ip route del default via 0.0.0.0 dev wg3 table rt_redacted
                          #   #   ${pkgs.iproute2}/bin/ip rule del iif wgbr3 lookup rt_redacted
                          #   #   ${pkgs.iproute2}/bin/ip rule del oif wgbr3 lookup rt_redacted
                          #   #   ${pkgs.iproute2}/bin/ip rule del iif wg3 lookup rt_redacted
                          #   #   ${pkgs.iproute2}/bin/ip rule del oif wg3 lookup rt_redacted
                          #   #   ${pkgs.iptables}/bin/iptables -D FORWARD -i wgbr3 -o wg3 -j ACCEPT
                          #   #   ${pkgs.iptables}/bin/iptables -D FORWARD -o wg3 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
                          #   #   ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -o wg3 -j MASQUERADE
                          #   #   '';

                          #   peers = [
                            #     {
                              #       publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

                              #       # redacted's DNS server + (all IPs - RFC1918)
                              #       #allowedIPs = [ "0.0.0.0/32" ];
                              #       allowedIPs = [ "0.0.0.0/32" "0.0.0.0/5" "0.0.0.0/7" "0.0.0.0/8" "0.0.0.0/6" "0.0.0.0/4" "0.0.0.0/3" "0.0.0.0/2" "0.0.0.0/3" "0.0.0.0/5" "0.0.0.0/6" "0.0.0.0/12" "0.0.0.0/11" "0.0.0.0/10" "0.0.0.0/9" "0.0.0.0/8" "0.0.0.0/7" "0.0.0.0/4" "0.0.0.0/9" "0.0.0.0/11" "0.0.0.0/13" "0.0.0.0/16" "0.0.0.0/15" "0.0.0.0/14" "0.0.0.0/12" "0.0.0.0/10" "0.0.0.0/8" "0.0.0.0/7" "0.0.0.0/6" "0.0.0.0/5" "0.0.0.0/4" ];

                              #       # note: need to do some firewall stuff for handshake to work, see:
                              #       # https://discourse.nixos.org/t/solved-minimal-firewall-setup-for-wireguard-client/7577
                              #       endpoint = "0.0.0.0:3226";
                              #     }
                              #   ];
                              # };

                              # will put test2 in here, eventually
                              # wg3 = {
                                #
                                # };
                                
                };

                #networking.wireless.extraConfig = ''
                #  debug_level=0
                #'';

                #networking.networkmanager.settings.device.wifi.backend = "${pkgs.wpa_supplicant}/bin/wpa_supplicant";
                #networking.networkmanager.settings.device.wifi.wpa_supplicant_args = "-q";
                systemd.services.wpa_supplicant.serviceConfig = {
                  ExecStart = [
                    ""  # This empty string clears the existing ExecStart
                    "${pkgs.wpa_supplicant}/bin/wpa_supplicant -u -q"
                  ];
                };

                hardware.bluetooth.enable = true;
                hardware.sensor.iio.enable = true;

                #services.monado.enable = true;
                #services.monado.defaultRuntime = true;

                fonts.packages = with pkgs; [
                  noto-fonts
                  noto-fonts-cjk-sans
                  noto-fonts-emoji
                  liberation_ttf
                  fira-code
                  fira-code-symbols
                  mplus-outline-fonts.githubRelease
                  dina-font
                  proggyfonts
                  # nerdfonts
                  corefonts
                ];

                gtk.iconCache.enable = true;
                services.xserver = {
                  enable = true;
                  displayManager.gdm.enable = true;
                  desktopManager.gnome.enable = true;
                };
                services.displayManager.sessionPackages = [ pkgs.sway ];
                # services.dbus.enable = true;
                # xdg.portal = {
                  #   enable = true;
                  #   wlr.enable = true;
                  #   # gtk portal needed to make gtk apps happy
                  #   extraPortals = lib.mkForce [ pkgs.xdg-desktop-portal-gtk pkgs.xdg-desktop-portal-wlr ];
                  # };

                  # fixes file conflict with some portal-related file
                  xdg.portal.extraPortals = lib.mkForce [ pkgs.xdg-desktop-portal-gtk pkgs.xdg-desktop-portal-wlr ];
                  programs.sway = {
                    enable = true;
                    extraOptions = [
                      "--unsupported-gpu"
                    ];
                    wrapperFeatures.gtk = true; # so that gtk works properly
                    extraPackages = with pkgs; [
                      swaylock
                      swayidle
                      wl-clipboard
                      mako # notification daemon
                      alacritty # Alacritty is the default terminal in the config

                      #     waybar

                      #     #       nwg-menu
                      #     # #      nwg-panel
                      #     #       nwg-drawer
                      #     #       nwg-wrapper
                      #     #       nwg-launchers

                      dmenu

                      grim
                      slurp
                      
                      wlogout
                    ];
                  };

                  services.gnome.gnome-keyring.enable = true;

                  # needed for oculus quest, MTP support
                  services.gvfs.enable = true;

                  #services.pcscd.enable = true;
                  programs.gnupg.agent = {
                    enable = true;
                    pinentryPackage = pkgs.pinentry-gnome3;
                  };

                  security.pam.loginLimits = [
                    { domain = "@users"; item = "rtprio"; type = "-"; value = 1; }
                  ];

                  programs.wireshark.enable = true;

                  services.displayManager.defaultSession = "gnome";
                  services.displayManager.autoLogin = {
                    enable = true;
                    user = "clownpiece";
                  };

                  # workaround for https://nixos.wiki/wiki/GNOME#automatic_login
                  systemd.services."getty@tty1".enable = false;
                  systemd.services."autovt@tty1".enable = false;

                  services.pulseaudio.enable = false;
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
                    systemWide = false;
                  };

                  hardware.nvidia-container-toolkit.enable = true;
                  virtualisation.lxd = {
                    enable = true;
                    ui.enable = true;
                  };
                  virtualisation.podman = {
                    enable = true;
                    enableNvidia = true;
                    extraPackages = with pkgs; [
                      dive
                      podman-compose
                      podman-tui
                    ];
                  };
                  virtualisation.docker = {
                    enable = true;

                    enableNvidia = true;
                    storageDriver = "zfs";
                    daemon.settings = {
                      storage-opts = [ "zfs.fsname=bell/docker" ];
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
                    gnomeExtensions.workspace-matrix
                    gnomeExtensions.appindicator
                    gnomeExtensions.screen-rotate
                    gnomeExtensions.bing-wallpaper-changer
                    gnomeExtensions.kimpanel
                    gnomeExtensions.gtk4-desktop-icons-ng-ding
                    gnome-terminal
                    efibootmgr
                    sbctl
                    dislocker
                    ntfs3g
                    vulkan-tools
                    bridge-utils
                    xorg.xhost
                    wayland-utils
                    evtest
                    nvtopPackages.full
                    nethogs
                    iotop
                    smem
                    gnome-tweaks
                    memtree
                    sqlite
                    sqlitebrowser
                    zotero
                    nftables
                    virt-viewer
                    #freecad
                    smartmontools
                  ];

                  services.udev.packages = with pkgs; [ gnome-settings-daemon ];
                  services.udev.extraRules = ''
                    SUBSYSTEM=="input", ATTRS{id/vendor}=="2dc8", ATTRS{id/product}=="6101", SYMLINK+="input/by-id/8bitdo-sn30-pro", MODE="0660", GROUP="games"
                  '';

                  users.groups.magician.gid = 381;
                  users.groups.games.gid = 382;
                  users.groups.agent.gid = 384;

                  users.users.root.subUidRanges = lib.mkForce [{ startUid = 1000000; count = 16777216; }];
                  users.users.clownpiece = {
                    uid = 1000;
                    subUidRanges = [
                      { startUid = 100000; count = 16777216; }
                      { startUid = 4204; count = 1; }
                    ];
                    subGidRanges = [
                      { startGid = 100000; count = 16777216; }  # Default range
                      { startGid = config.ids.gids.audio; count = 1; }
                      { startGid = config.ids.gids.video; count = 1; }
                      { startGid = config.ids.gids.render; count = 1; }
                      { startGid = config.users.groups.games.gid; count = 1; }
                    ];
                    extraGroups = [ "magician" "wheel" "audio" "video" "sudo" "render" "networkmanager" "docker" "podman" "libvirtd" "wireshark" "lxd" "input" "games" "plugdev" "pipewire" "lp" "scanner" "adbusers" "kvm"];
                    isNormalUser = true;
                  };

                  users.users.flandre = {
                    uid = 4204;
                    extraGroups = [ "audio" "video" "render" "input" "plugdev" "pipewire" "games" ];
                    isNormalUser = true;
                  };

                  users.users.claude = {
                    uid = 4738; # i asked him
                    group = "agent";
                    extraGroups = [ ];
                    isNormalUser = true;
                  };

                  users.users.seiran = {
                    uid = 5912;
                    extraGroups = [ "wheel" "video" "sudo" "render" "networkmanager" "docker" "podman" "libvirtd" "wireshark" "lxd" "input" "plugdev" "pipewire" "lp" "scanner" "adbusers" "kvm"];
                    isNormalUser = true;
                  };

                  system.stateVersion = "24.11"; # Did you read the comment?
}
