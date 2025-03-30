{ lib, pkgs, dotfiles, ... }: {
#let
  # myEmacs = (pkgs.emacsWithPackagesFromUsePackage {
  #   package = pkgs.emacs29-pgtk;  # replace with pkgs.emacsPgtk, or another version if desired.
  #   config = ../../emacs/config.el;
  #   defaultInitFile = false;

  #   # Optionally provide extra packages not in the configuration file.
  #   extraEmacsPackages = epkgs: [
  #     epkgs.use-package
  #     pkgs.chez
  #     pkgs.terraform-ls
  #   ];

  #   # Optionally override derivations.
  #   # override = epkgs: epkgs // {
  #   #   somePackage = epkgs.melpaPackages.somePackage.overrideAttrs(old: {
  #   #      # Apply fixes here
  #   #   });
  #   # };
  # });
  #  local_infra = import ./local_pkgs.nix { inherit pkgs; };
 
  #in {
  #nixpkgs.overlays = [
  #  emacs-overlay.overlays.default
  #];
  #home.packages = with pkgs; [emacs29-pgtk];
  home.sessionVariables = {
    "QT_QPA_PLATFORM" = "wayland";
    #  "QT_WAYLAND_FORCE_DPI" = "physical";
    #  "ECORE_EVAS_ENGINE" = "wayland_egl";
    #  "ELM_ENGINE" = "wayland_egl";
    "SDL_VIDEODRIVER" = "wayland";
    "_JAVA_AWT_WM_NONREPARENTING" = "1";
    "MOZ_ENABLE_WAYLAND" = "1";
    "SAL_USE_VCLPLUGIN" = "gtk3";
    "PATH" ="$HOME/.local/bin:$PATH";
    #  "COLORTERM" = "truecolor"; # it is the year two-thousand and twenty-three
    "GLFW_IM_MODULE" = "ibus";
  };

  i18n.inputMethod = {
    enabled = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      fcitx5-gtk
    ];
    #ibus.engines = with pkgs.ibus-engines; [ anthy ];
  };

  programs.home-manager.enable = true;

  home.packages = let
    nix_thirdparty = with pkgs; [
      #      nix-du
      #      nix-index
      #      nix-prefetch-scripts
      #      nix-tree
    ];
    base_pkgs = with pkgs; [
      bc
      bind
      curl
      #dmidecode
      #      emacs-nox
      #neovim
      fdupes
      jq
      yq
      file
      #gnum4
      git
      #gnupg
      #gnutar
      gzip
      htop
      inetutils
      #inotify-tools
      iperf
      lsof
      lz4
      #mg
      mosh
      #moreutils
      #proxychains-ng
      nmap
      #ntfs3g
      p7zip
      parallel
      pari
      psmisc
      pv
      rclone
      #recode
      rlwrap
      rsync
      #screenfetch
      neofetch
      netcat
      speedtest-cli
      #sqlite
      sysstat
      tmux
      screen
      #      unrar
      unzip
      pciutils
      usbutils
      wget
      which
      xz
      xxd
      zip
      unrar-wrapper
      tree
    ];
    desktop_pkgs = with pkgs; [
      #gnome.adwaita-icon-theme
      #arandr
      #filelight
      #breeze-qt5
      chromium
      # dfeet
      #dconf
      #desktop-file-utils
      #dmenu
      #gnome.dconf-editor
      #element-desktop-wayland
      element-desktop
      #      emacs-gtk
      #      emacsPgtk
      # myEmacs
      #foliate
      #okular
      #evolution
      #evtest
      exif
      feh
      ffmpeg
      ffmpegthumbnailer
      file-roller
      #gnome.gnome-calendar
      #konsole
      #lxappearance
      #filezilla
      firefox-wayland
      #cdrkit
      #cuetools
      flac
      #gedit
      gimp
      glxinfo
      #gsettings-desktop-schemas
      #gvfs
      #hamster
      #hexchat
      #hicolor-icon-theme
      #hplip
      keepassxc
      #liberation_ttf
      #dunst
      libreoffice
      #megatools
      qbittorrent
      mpv
      #      nerdfonts
      pavucontrol
      #pcmanfm
      #read-edid
      #scrot
      sshfs-fuse
      trash-cli
      vlc
      wireshark-qt
      #wmctrl
      #xarchiver
      #xbindkeys
      #xbindkeys-config
      #xscreensaver
      #xclip
      xorg.xclock
      #xdotool
      xorg.xev
      xorg.xeyes
      #xorg.xhost
      #youtube-dl
      yt-dlp
      #streamlink
      #gnome.zenity
      #wdisplays
      #kanshi
      komikku
      foliate
      remmina
      flatpak
      flatpak-builder
      gnome-software
    ];
    dev_pkgs = with pkgs; [
      aliyun-cli
      cloc
      colordiff
      #    coq
      # ddd
      #eclipses.eclipse-platform
      #gdb
      #      gdbgui
      #ghc
      #glade
      #sqlitebrowser
      #subversion
      virt-manager
      #docker
      #docker-compose
      #vscodium
      #xfig
      #qemu
      #stdenv
      gnumake
      awscli2
      flarectl
      (pkgs.terraform.withPlugins (p: [
        p.null
        p.tls
        p.aws
        p.libvirt
      ]))
      git-lfs
      # fixme: haskell lsp demands that these are in $PATH for some bizarre reason
      ghc
      cabal-install
      haskell-language-server
    ];
    # my_ghidra = pkgs.ghidra.overrideAttrs (oldAttrs: {
    #   pname = "${oldAttrs.pname}-patched";
    #   postFixup = ''
    #   ${oldAttrs.postFixup or ""}
    #   sed -i 's/-Dsun.java2d.uiScale=1/-Dsun.java2d.uiScale=2/' $out/lib/ghidra/support/launch.properties
    # '';
    # });
    local_pkgs = with pkgs; [
      blender
      audacity
      krita
      obs-studio
      #      calibre
      # inkscape
      # gzdoom
      syncplay
      ossutil
      anki
      ghidra
      wl-clipboard
      prismlauncher
    ];
    shell_scripts = with pkgs; [
      (writeShellScriptBin "mktemp_home" (builtins.readFile "${dotfiles}/bin/mktemp_home.sh"))
      (writeShellScriptBin "random_passwd" (builtins.readFile "${dotfiles}/bin/random_passwd.sh"))
      (writeShellScriptBin "random_hex" (builtins.readFile "${dotfiles}/bin/random_hex.sh"))
    ];
  in lib.concatLists [nix_thirdparty base_pkgs desktop_pkgs dev_pkgs local_pkgs shell_scripts];

  programs.bash.enable = true;

  # shellAliases = {
  #   example = "true";
  # };

  programs.emacs = {
    enable = true;
    package = pkgs.emacs30-pgtk;
    extraPackages = let
      lean4-mode = {
        trivialBuild,
        fetchFromGitHub,
        lean4,
        dash,
        lsp-mode,
        magit-section
      }:
      trivialBuild rec {
        pname = "lean4-mode";
        version = "1.1.2";
        src = fetchFromGitHub {
          owner = "leanprover-community";
          repo = "lean4-mode";
          rev = "76895d8939111654a472cfc617cfd43fbf5f1eb6";
          hash = "sha256-DLgdxd0m3SmJ9heJ/pe5k8bZCfvWdaKAF0BDYEkwlMQ=";
        };
        postInstall = ''
          mkdir -p $out/share/emacs/site-lisp/data/
          cp -p $src/data/abbreviations.json $out/share/emacs/site-lisp/data/
        '';
        propagatedUserEnvPkgs = [ lean4 dash lsp-mode magit-section ];
        buildInputs = propagatedUserEnvPkgs;
      };
    in epkgs: [
      pkgs.chez
      pkgs.terraform-ls
      pkgs.haskell-language-server
      pkgs.ghc
      epkgs.use-package
      epkgs.forth-mode
      epkgs.go-mode
      epkgs.flycheck
      epkgs.lsp-mode
      epkgs.lsp-haskell
      (epkgs.callPackage lean4-mode {})
    ];

    # i do not recall what problem this was intended to fix...
    extraConfig = ''
      (when (not (boundp 'site-lisp-config))
        (setq site-lisp-config "${dotfiles}/emacs/config.el"))
      (load-file site-lisp-config)
    '';
  };

  programs.neovim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [
      nvim-tree-lua
      nvim-web-devicons
      nvim-lspconfig
      lean-nvim
    ];
    extraPackages = with pkgs; [ lean4 ];
  };

  # programs.vscode = {
  #   enable = true;
  #   package = pkgs.vscodium;
  #   extensions = with pkgs.vscode-extensions; [
  #     dracula-theme.theme-dracula
  #     vscodevim.vim
  #     yzhang.markdown-all-in-one
      
  #   ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
  #     {
  #       name = "lean4";
  #       publisher = "leanprover";
  #       version = "0.0.177";
  #       sha256 = "sha256-4roh1M5F4eIX0UNNDCfO47zgJAL+nRnHUAD///4hbok=";
  #     }
  #   ];
  #   userSettings = {
  #     "lean4.elanPath" = "${pkgs.elan}/bin/elan";
  #     "lean4.executablePath" = "${pkgs.lean4}/bin/lean";
  #   };
  # };

  manual.manpages.enable = true;

  home.stateVersion = "24.11";
}
