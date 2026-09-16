{ config, lib, pkgs, ... }: let
  unfreePkgNames = [
    "corefonts"
    "vcv-rack"
    # fixme: i don't actually want this directly in the system derivation... i
    # only want the sandbox launcher in the system derivation
    "bitwig-studio"
    "bitwig-studio-unwrapped"
    "bitwig-studio-unwrapped-6.0"
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

  boot.blacklistedKernelModules = [ "dvb_usb_rtl28xxu" ];

  #boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  #system.nixos.tags = [ "lts-kernel" ];
  # linuxPackages refers to latest lts kernel
  boot.kernelPackages = pkgs.linuxPackages;
  # at the time of writing, this is equal to zfs_unstable
  boot.zfs.package = pkgs.zfs_unstable;

  #specialisation = {
    # stable refers to latest (per nixpkgs) stable branch kernel
    #stable.configuration = {
      #boot.kernelPackages = pkgs.linuxPackages_latest;
      #system.nixos.tags = lib.mkForce [ "stable-kernel" ];
    #};
  #};

  # hardware.bluetooth lives in lib/desktop.nix
  hardware.sensor.iio.enable = true;
  hardware.rtl-sdr.enable = true;
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    prime.amdgpuBusId = "PCI:1:0:0";
    prime.nvidiaBusId = "PCI:105:0:0";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" "cgroups" ];
  nix.settings.use-cgroups = true;
  nix.settings.trusted-users = [ "clownpiece" "seiran" ];

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

  networking.firewall.trustedInterfaces = [ "incusbr0" ];
  # networking.firewall.interfaces.incusbr0 = {
  #   allowedUDPPorts = [ 53 67 ];
  # };
  # networking.firewall.extraForwardRules = ''
  #   iifname "incusbr0" accept
  #   oifname "incusbr0" ct state established,related accept
  # '';

  networking.nftables.enable = true;

  services.tailscale.enable = true;
  services.tailscale.extraSetFlags = [ "--accept-routes" ];
  services.tailscale.useRoutingFeatures = "client";

  networking.iproute2.enable = true;
  
  # this means we don't need reverse-routes for everything in the routing table
  networking.firewall.checkReversePath = "loose";
  networking.firewall.rejectPackets = true;

  #i18n.supportedLocales = [
  #  "en_US.UTF-8/UTF-8"
  #  "ja_JP.UTF-8/UTF-8"
  #  "ja_JP.SJIS"
  #];

  # Enable the OpenSSH server.
  services.sshd.enable = true;
  services.guix.enable = true;

  services.printing = {
    enable = true;
    drivers = [pkgs.hplip pkgs.brlaser];
  };
  
  #programs.adb.enable = true;
  programs.wireshark.enable = true;
  #services.fprintd.enable = lib.mkForce false;
  powerManagement.enable = true;
  #services.tlp.enable = true;
  services.flatpak.enable = true;
  
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  programs.hyprland.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  services.displayManager.defaultSession = "gnome";
  services.displayManager.autoLogin = {
    enable = true;
    user = "clownpiece";
  };

  services.pulseaudio.enable = false;
  # sound.enableOSSEmulation = true;
  # rtkit + pipewire live in lib/desktop.nix

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
    ultimate-oldschool-pc-font-pack
  ];

  fonts.fontconfig.localConf = ''
    <match target="font">
      <test name="family" compare="contains"><string>IBM VGA</string></test>
      <edit name="antialias" mode="assign"><bool>false</bool></edit>
      <edit name="hinting" mode="assign"><bool>false</bool></edit>
    </match>
  '';

  fonts.fontDir.enable = true;

  security.auditd.enable = true;
  security.audit.enable = true;
  security.auditd.plugins = {
      syslog = {
        path = lib.getExe' config.security.auditd.package "audisp-syslog";
        args = [ "LOG_INFO" ];
      };
  };
  security.audit.rules = [
    "-a always,exit -F arch=b64 -S execve -F uid=${builtins.toString config.users.users.claude.uid} -k claude-exec"
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
    package = pkgs.incus;
    ui.enable = true;
    #bucketSupport = false;
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

  services.sanoid = {
    enable = true;
    datasets."bell/workspace/miu" = {
      autosnap = true;
      autoprune = true;
      frequently = 4;
      frequent_period = 15;
      hourly = 36;
      daily = 30;
      monthly = 3;
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
    #memtree
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
    rtl-sdr
    gqrx
    element
    element-desktop
    android-tools
    tor-browser
    ghostty
    foot
    xorg.xauth
  ];

  users.groups.magician.gid = 381;
  users.groups.games.gid = 382;
  users.groups.agent.gid = 384;

  users.users.root.subUidRanges = lib.mkForce [
    { startUid = 1000000; count = 1000000000; }
    { startUid = config.users.users.clownpiece.uid; count = 1; }
    { startUid = config.users.users.flandre.uid; count = 1; }
  ];
  users.users.root.subGidRanges = lib.mkForce [
    { startGid = 1000000; count = 1000000000; }
    { startGid = config.ids.gids.audio; count = 1; }
    { startGid = config.ids.gids.video; count = 1; }
    { startGid = config.ids.gids.render; count = 1; }
    { startGid = config.users.groups.agent.gid; count = 1; }
    { startGid = config.users.groups.games.gid; count = 1; }
  ];
  users.users.clownpiece = {
    uid = 1000;
    # subUidRanges = [
    #   { startUid = 100000; count = 16777216; }
    #   { startUid = config.users.users.clownpiece-audio.uid; count = 1; }
    #   { startUid = config.users.users.flandre.uid; count = 1; }
    #   { startUid = config.users.users.claude.uid; count = 1; }
    # ];
    # subGidRanges = [
    #   { startGid = 100000; count = 16777216; }  # Default range
    #   { startGid = config.ids.gids.audio; count = 1; }
    #   { startGid = config.ids.gids.video; count = 1; }
    #   { startGid = config.ids.gids.render; count = 1; }
    #   { startGid = config.users.groups.agent.gid; count = 1; }
    #   { startGid = config.users.groups.kvm.gid; count = 1; }
    #   { startGid = config.users.groups.games.gid; count = 1; }
    #   { startGid = config.users.users.clownpiece-audio.uid; count = 1; }
    # ];
    extraGroups = [ "magician" "wheel" "audio" "video" "sudo" "render" "networkmanager" "docker" "podman" "libvirtd" "wireshark" "incus" "incus-admin" "input" "games" "plugdev" "pipewire" "lp" "scanner" "adbusers" "kvm"];
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

  users.users.seiran = {
    uid = 5912;
    extraGroups = config.users.users.clownpiece.extraGroups;
    isNormalUser = true;
  };

  nix.settings.allowed-users = [ "claude" ];

  system.stateVersion = "24.11"; # Did you read the comment?
}
