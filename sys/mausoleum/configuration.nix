{ config, lib, pkgs, modulesPath, ... }: let 
  local_infra = import ../../default.nix { pkgs = pkgs; };
in {
 # nixpkgs.config.allowlistedLicenses = with lib.licenses; [ bsl11 ];

  boot.loader.systemd-boot.enable = true;
  #boot.loader.grub.enable = true;
  #boot.loader.grub.device = "/dev/disk/by-uuid/REDACTED";
  boot.loader.efi.canTouchEfiVariables = true;

  #networking.hostName = "mausoleum"; 
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

    services.thermald.enable = true;

  # nix.buildMachines = [ {
	#   hostName = "mausoleum";
	#   system = "x86_64-linux";
  #   protocol = "ssh-ng";
	#   maxJobs = 12;
	#   speedFactor = 2;
	#   supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
	#   mandatoryFeatures = [ ];
	# }] ;
	# nix.distributedBuilds = true;
	# # optional, useful when the builder has a faster internet connection than yours
	# nix.extraOptions = ''
  #     builders-use-substitutes = true
	#   '';

  #services.xserver.enable = true;
  #services.xserver.layout = "us";
  #services.xserver.displayManager.sddm.enable = true;
  #services.xserver.displayManager.setupCommands = ''
  #xrandr 
  #'';
  #sound.enableOSSEmulation = true;
  # xdg.portal.enable = true;
  # xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
  # fonts.fonts = with pkgs; [
  #   noto-fonts
  #   noto-fonts-cjk
  #   noto-fonts-emoji
  #   liberation_ttf
  #   fira-code
  #   fira-code-symbols
  #   #mplus-outline-fonts
  #   dina-font
  #   proggyfonts
  #   unifont unifont_upper font-awesome
  # ];
  # programs.nm-applet.indicator = true;

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
  };

  # programs.sway = {
  #   enable = true;
  #   #wrapperFeatures.gtk = true; # so that gtk works properly
  #   extraPackages = with pkgs; [
  #     swaylock
  #     swayidle
  #     wl-clipboard
  #     mako # notification daemon
  #     alacritty # Alacritty is the default terminal in the config

  #     #waybar

  #     #nwg-menu
  #     #      nwg-panel
  #     #nwg-drawer
  #     #nwg-wrapper
  #     #nwg-launchers

  #     grim
  #     slurp
      
  #     wlogout
  #     hicolor-icon-theme
  #   ];
  # };

  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  systemd.services."display-manager".enable = false;
  services.xserver.desktopManager.gnome.enable = true;
  programs.dconf.enable = true;

  services.xrdp.enable = true;
  services.xrdp.audio.enable = true;
  services.xrdp.port = 3389;
  #services.xrdp.defaultWindowManager = "gnome-session";
  services.xrdp.extraConfDirCommands = ''
    substituteInPlace $out/sesman.ini \
      --replace AllowRootLogin=true AllowRootLogin=false \
      --replace RestrictOutboundClipboard=none RestrictOutboundClipboard=all \
      --replace RestrictInboundClipboard=none RestrictInboundClipboard=all
  '';
  services.avahi.enable = false;

  # Configure keymap in X11
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  # users.users.alice = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
  #   packages = with pkgs; [
  #     firefox
  #     tree
  #   ];
  # };
  users.users.yoshika = {
    isNormalUser = true;
    extraGroups = ["wheel" "video"];
  };
  users.users."root".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted"
  ];

  # home-manager.useUserPackages = true;
  # home-manager.useGlobalPkgs = true;
  # home-manager.users.rumia = let
  #   # TODO: factor this out, the hard part is the overlay...
  #   myEmacs = (pkgs.emacsWithPackagesFromUsePackage {
  #     package = pkgs.emacs-pgtk;  # replace with pkgs.emacsPgtk, or another version if desired.
  #     config = ../../emacs/config.el;
  #     defaultInitFile = false;

  #     # Optionally provide extra packages not in the configuration file.
  #     extraEmacsPackages = epkgs: [
  #       epkgs.use-package
  #     ];

  #     # Optionally override derivations.
  #     # override = epkgs: epkgs // {
  #     #   somePackage = epkgs.melpaPackages.somePackage.overrideAttrs(old: {
  #     #      # Apply fixes here
  #     #   });
  #     # };
  #   });
  #   base_pkgs = local_infra.basepkgs;
  #   desktop_pkgs = local_infra.desktop_pkgs;
  #   dev_pkgs = local_infra.dev_pkgs;
  #   local_pkgs = local_infra.local_pkgs;
  # in { pkgs, ...}: {
  #   home.packages = base_pkgs ++ desktop_pkgs ++ [myEmacs] ++ dev_pkgs ++ local_pkgs;
  #   home.sessionVariables = {
  #     "QT_QPA_PLATFORM" = "wayland-egl";
  #     "QT_WAYLAND_FORCE_DPI" = "physical";
  #     "ECORE_EVAS_ENGINE" = "wayland_egl";
  #     "ELM_ENGINE" = "wayland_egl";
  #     "SDL_VIDEODRIVER" = "wayland";
  #     "_JAVA_AWT_WM_NONREPARENTING" = "1";
  #     "MOZ_ENABLE_WAYLAND" = "1";
  #     "SAL_USE_VCLPLUGIN" = "gtk3";
  #     "PATH" ="$HOME/.local/bin:$PATH";
  #   };
  #   manual.manpages.enable = false;
  #   home.stateVersion = "23.05";
  # };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    gnumake
    wget
    sbctl
    efibootmgr
    pv
    #     jfbpdf
    # fbvnc
    # fbcat
    # #     jfbview
    # fbv
    # fbmark
    # fbida
    # fbpdf
    # links2
    # ranger
    # mc
    # so
    # sc-im
    # htop-vim
    # htop
    # tmux
    # pari
    # weechat
    # #     tty-studio
    # neofetch
    # tty-clock
    # yewtube
    # vlc
    # mpv
    # pipes
    # rtorrent
    # #     newsbeuter
    # newsboat
    # nethogs
    # wego
    # git
    # curl
    # w3m-nox
    # mutt
    # moc
    # ttyplot
    # ovh-ttyrec
    # physlock
    #x11vnc
    #xrdp
    gtk4
    hydrus
  ];

  # TODO: not ideal to specify a commit here...
  # i don't want it to update every time the upstream gets updated, because
  # that generally triggers lengthy and annoying rebuilds of emacs
  # but i don't want to have to remember to update it either because that's
  # also annoying. maybe git submodules + Grand Unified Update Script that
  # automatically moves them to the most recent master commit?
  #nixpkgs.overlays = [
  #  (import (builtins.fetchGit {
  #    url = "https://github.com/nix-community/emacs-overlay.git";
  #    ref = "master";
  #    rev = "074dc30cec64604d650fffcb90631f63900d76d9"; # change the revision
  #  }))
  #];

  #system.copySystemConfiguration = true;
  system.stateVersion = "23.05"; # Did you read the comment?
}
