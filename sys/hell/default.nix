{ config, lib, pkgs, ... }: let
  unfreePkgNames = [
    "claude-code" # lib/agent.nix
    "corefonts"
    "vcv-rack"
  ];

  # fixme: is there really no clean way to modularize this
  nvidiaPkgNames = [
    "nvidia-x11"
    "nvidia-persistenced"
    "nvidia-settings"
    "cudnn"
  ];
  nvidiaLicenses = [
    "CUDA EULA"
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

in {
  nixpkgs.config.allowUnfreePredicate = let
    unfreePredicate = pkg: builtins.elem (lib.getName pkg) unfreePkgNames;
  in pkg: (nvidiaUnfreePredicate pkg) || (unfreePredicate pkg);

  boot.kernelParams = [
    "cgroup_enable=memory"
    "systemd.unified_cgroup_hierarchy=1"
  ];

  boot.kernel.sysctl = {
    "vm.min_free_kbytes" = 524288;
  };

  # linuxPackages refers to latest lts kernel
  boot.kernelPackages = pkgs.linuxPackages;

  # hardware.bluetooth lives in lib/desktop.nix
  hardware.sensor.iio.enable = true;
  hardware.rtl-sdr.enable = true;

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
    CPUWeight = 50;         # Lower than default (100)

    MemoryHigh = "16G";
    MemoryMax = "20G";

    IOWeight = 50;          # Lower than default (100)

    Slice = "swap-allowed.slice";
  };
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  networking.firewall.trustedInterfaces = [ "incusbr0" ];

  networking.nftables.enable = true;

  services.tailscale.enable = true;
  services.tailscale.extraSetFlags = [ "--accept-routes" ];
  services.tailscale.useRoutingFeatures = "client";

  networking.iproute2.enable = true;
  
  # this means we don't need reverse-routes for everything in the routing table
  networking.firewall.checkReversePath = "loose";
  networking.firewall.rejectPackets = true;

  services.sshd.enable = true;
  services.guix.enable = true;

  services.printing = {
    enable = true;
    drivers = [pkgs.hplip pkgs.brlaser];
  };
  
  programs.wireshark.enable = true;
  powerManagement.enable = true;
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

  virtualisation.incus = {
    enable = true;
    package = pkgs.incus;
    ui.enable = true;
  };
  virtualisation.podman = {
    enable = true;
    extraPackages = with pkgs; [
      dive
      podman-compose
      podman-tui
    ];
  };
  virtualisation.docker = {
    enable = true;
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
    gnomeExtensions.workspace-matrix
    gnomeExtensions.appindicator
    gnomeExtensions.screen-rotate
    gnomeExtensions.bing-wallpaper-changer
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
    sqlite
    sqlitebrowser
    lyx
    nftables
    virt-viewer
    smartmontools
    libimobiledevice
    ifuse
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
  ] ++ lib.optionals (!config.gensokyo.ci) [
    # large, uncached builds (zotero drags its own firefox-esr in); the
    # home profile's large_pkgs is the same idea
    zotero
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
}
