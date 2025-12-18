{ config, lib, pkgs, ... }: let
  unfreePkgNames = [
    "corefonts"
    "vcv-rack"
    # fixme: i don't actually want this directly in the system derivation... i
    # only want the sandbox launcher in the system derivation
    "bitwig-studio-unwrapped" 
  ];

  # fixme: is there really no clean way to modularize this
  nvidiaPkgNames = [
    "nvidia-x11"
    "nvidia-persistenced"
    "nvidia-settings"
    "cudnn"
    #    "cuda_cudart"
    #    "cuda_cccl"
    #    "libcublas"
    #    "nvtop"
  ];
  nvidiaLicenses = [
    "CUDA EULA"
    #    "cuDNN EULA"
    #    "cuTENSOR EULA"
    "NVidia OptiX EULA"
  ];
  nvidiaUnfreePredicate = let
    nvidiaNamePred = pkg: (builtins.elem (lib.getName pkg) nvidiaPkgNames);
    nvidiaLicensePred = pkg: let
      pkgLicenses = if builtins.isList pkg.meta.license
                    then pkg.meta.license
                    else [ pkg.meta.license ];
    in builtins.all (license:
      license.free || builtins.elem license.shortName nvidiaLicenses) pkgLicenses;
  in pkg: (nvidiaNamePred pkg) || (nvidiaLicensePred pkg);

  RFC1918Addresses = [ "0.0.0.0/5" "0.0.0.0/7" "0.0.0.0/8" "0.0.0.0/6" "0.0.0.0/4" "0.0.0.0/3" "0.0.0.0/2" "0.0.0.0/3" "0.0.0.0/5" "0.0.0.0/6" "0.0.0.0/12" "0.0.0.0/11" "0.0.0.0/10" "0.0.0.0/9" "0.0.0.0/8" "0.0.0.0/7" "0.0.0.0/4" "0.0.0.0/9" "0.0.0.0/11" "0.0.0.0/13" "0.0.0.0/16" "0.0.0.0/15" "0.0.0.0/14" "0.0.0.0/12" "0.0.0.0/10" "0.0.0.0/8" "0.0.0.0/7" "0.0.0.0/6" "0.0.0.0/5" "0.0.0.0/4" ];
in rec {
  nixpkgs.config.allowUnfreePredicate = let
    unfreePredicate = pkg: builtins.elem (lib.getName pkg) unfreePkgNames;
  in pkg: (nvidiaUnfreePredicate pkg) || (unfreePredicate pkg);

  nixpkgs.overlays = [
    # (self: super: {
    #   linuxPackages_6_14 = super.linuxPackages_6_14.extend (lpself: lpsuper: {
    #     zfs_unstable = lpsuper.zfs_unstable.overrideAttrs (oldAttrs: {
    #       meta = oldAttrs.meta // { broken = true; }; # remove whenever you feel like it
    #     });
    #   });
    #   my_zfs = super.zfs_unstable.overrideAttrs(old: {
    #     kernelCompatible = true;
    #     #meta.broken = false;
    #     #rev = "301da593ade391fa78a660c7b42325cd2ace593a";
    #   });
    # })
  ];

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

  boot.kernelParams = [
    "zfs.zfs_arc_min=536870912"
    "zfs.zfs_arc_max=2147483648"
    "cgroup_enable=memory"
    "systemd.unified_cgroup_hierarchy=1"
    # found online, might reduce stuttering?
    # "amdgpu.preempt_mm=0"
  ];

  boot.kernel.sysctl = {
    "vm.min_free_kbytes" = 524288;
  };

  system.nixos.tags = [ "lts-kernel" ];
  boot.kernelPackages = pkgs.linuxPackages;
  # at the time of writing, this is equal to zfs_unstable
  boot.zfs.package = pkgs.zfs_unstable;

  specialisation = {
    stable.configuration = {
      boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
      system.nixos.tags = lib.mkForce [ "stable-kernel" ];
    };
  };

  hardware.bluetooth.enable = true;
  hardware.sensor.iio.enable = true;
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.beta;
    prime.amdgpuBusId = "PCI:1:0:0";
    prime.nvidiaBusId = "PCI:105:0:0";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" "cgroups" ];
  nix.settings.use-cgroups = true;
  nix.settings.trusted-users = [ "clownpiece" ];

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

    MemoryHigh = "16G";
    MemoryMax = "20G";

    IOWeight = 50;          # Lower than default (100)
    #IOSchedulingClass = "idle";

    Slice = "swap-allowed.slice";
  };
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  # 

  networking.hostName = "hell";

  # some networking notes
  # we will want to use the wgN device with one or possibly multiple network namespaces, but it can only be in one at a time. so instead we keep it in the default namespace and create a bridge, and make veth pairs for each additional network namespace we want to use.
  # we also may not want to have any routing table rules in the default network namespace, because the interface may be for testing or other weird stuff. instead, we... wait, what do we do? it looks like we create a new routing table with the weird "multiple routing table" thingie, in the default netns. why do we need that... can't we just have the routing table in the namespace with the veth pair? what routing even happens in the default network namespace? in fact, i kind of specifically want there to not be any routing for wgN in the default netns, it will conflict with at least one other wgN (for the DNS server)
  
  networking.firewall.allowedUDPPorts = [
    config.networking.wireguard.interfaces.wg-redacted.listenPort
  ];

  networking.nftables.enable = true;

  services.tailscale.enable = true;

  networking.iproute2.enable = true;
  
  # this means we don't need reverse-routes for everything in the routing table
  networking.firewall.checkReversePath = "loose";
  networking.firewall.rejectPackets = true;

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
          endpoint = "0.0.0.0:3161";
        }
      ];

      # we need to set route weights, so do it manually
      allowedIPsAsRoutes = false;
      postSetup = ''
        ip route add 0.0.0.0/32 dev wg-redacted
      '';
    };
  };

  security.pki.certificateFiles = [
    ../../etc/certs/gensokyo.internal.ca.pem
  ];

  services.resolved.llmnr = "false";

  # Enable the OpenSSH server.
  services.sshd.enable = true;
  services.guix.enable = true;

  services.printing = {
    enable = true;
    drivers = [pkgs.hplip pkgs.brlaser];
  };
  
  programs.adb.enable = true;
  programs.wireshark.enable = true;
  #services.fprintd.enable = lib.mkForce false;
  powerManagement.enable = true;
  #services.tlp.enable = true;
  services.flatpak.enable = true;
  
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  programs.hyprland.enable = true;

  services.displayManager.defaultSession = "gnome";
  services.displayManager.autoLogin = {
    enable = true;
    user = "clownpiece";
  };

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

  gtk.iconCache.enable = true;

  services.gnome.gnome-keyring.enable = true;

  # needed for calendar to work with exchange
  programs.evolution.plugins = [ pkgs.evolution-ews ];
  services.gnome.evolution-data-server.plugins = [ pkgs.evolution-ews ];

  # needed for oculus quest, MTP support
  services.gvfs.enable = true;
  # for iPhone, etc
  services.usbmuxd.enable = true;

  services.udev.packages = with pkgs; [ gnome-settings-daemon ];
  services.udev.extraRules = ''
    SUBSYSTEM=="input", ATTRS{id/vendor}=="2dc8", ATTRS{id/product}=="6101", SYMLINK+="input/by-id/8bitdo-sn30-pro", MODE="0660", GROUP="games"
  '';

  services.pcscd.enable = true;
  programs.gnupg.agent = {
   enable = true;
   pinentryPackage = pkgs.pinentry-gnome3;
  };

  # fixme: package windows fonts, maybe...?
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
    # nerdfonts
    corefonts
  ];

  security.pam.loginLimits = [
    { domain = "@users"; item = "rtprio"; type = "-"; value = 1; }
  ];

  # workaround for https://nixos.wiki/wiki/GNOME#automatic_login
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.incus = {
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
    #gnomeExtensions.kimpanel
    gnomeExtensions.gtk4-desktop-icons-ng-ding
    gnomeExtensions.week-start-modifier
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
    lyx
    nftables
    virt-viewer
    #freecad
    smartmontools
    libimobiledevice
    ifuse # optional, to mount using 'ifuse'
    lean4
    gamescope
    please-cli
    libsecret
    dconf-editor
    desktop-file-utils
    imagemagick
    graphviz
    openssl
    dtach
    hunspell
    hunspellDicts.en_US
  ];

  users.groups.magician.gid = 381;
  users.groups.games.gid = 382;
  users.groups.agent.gid = 384;

  users.users.root.subUidRanges = lib.mkForce [{ startUid = 1000000; count = 16777216; }];
  users.users.clownpiece = {
    uid = 1000;
    subUidRanges = [
      { startUid = 100000; count = 16777216; }
      { startUid = 4204; count = 1; }
      { startUid = config.users.users.clownpiece-audio.uid; count = 1; }
    ];
    subGidRanges = [
      { startGid = 100000; count = 16777216; }  # Default range
      { startGid = config.ids.gids.audio; count = 1; }
      { startGid = config.ids.gids.video; count = 1; }
      { startGid = config.ids.gids.render; count = 1; }
      { startGid = config.users.groups.games.gid; count = 1; }
      { startGid = config.users.users.clownpiece-audio.uid; count = 1; }
    ];
    extraGroups = [ "magician" "wheel" "audio" "video" "sudo" "render" "networkmanager" "docker" "podman" "libvirtd" "wireshark" "lxd" "input" "games" "plugdev" "pipewire" "lp" "scanner" "adbusers" "kvm"];
    isNormalUser = true;
  };

  users.users.clownpiece-audio = {
    uid = 3280;
    group = "clownpiece-audio";
    extraGroups = [ "audio" "video" "render" "input" "plugdev" "pipewire"];
    isSystemUser = true;
  };
  users.groups.clownpiece-audio.gid = config.users.users.clownpiece-audio.uid;

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
    extraGroups = config.users.users.clownpiece.extraGroups;
    isNormalUser = true;
  };

  system.stateVersion = "24.11"; # Did you read the comment?
}
