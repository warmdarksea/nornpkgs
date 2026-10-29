{ lib, pkgs, osConfig ? { }, ... }: let
  # The CUDA-flavoured desktop packages (cuda_pkgs, below) only go in where
  # there is a GPU to use them *and* a machine that can build them:
  #   cudaEnabled follows the host's nixpkgs.config.cudaSupport, which is
  #               what makes blender & co. pull the CUDA toolchain in;
  #   ci          is gensokyo-private's ci branch flagging the GitHub
  #               Actions runner (lib/ci.nix), which must never build them.
  # osConfig is the NixOS config when home-manager runs as its module; under
  # standalone home-manager it is absent, hence the defaults.
  cudaEnabled = pkgs.config.cudaSupport or false;
  ci = osConfig.gensokyo.ci or false;
in {
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

  # i18n.inputMethod = {
  #   enabled = "fcitx5";
  #   fcitx5.addons = with pkgs; [
  #     fcitx5-mozc
  #     fcitx5-gtk
  #   ];
  #   #ibus.engines = with pkgs.ibus-engines; [ anthy ];
  # };

  programs.home-manager.enable = true;

  # Two tiers plus CUDA. small_pkgs is what the CI build keeps: cli tools,
  # light desktop utilities, and the toolchains programs.emacs drags in
  # regardless (ghc + haskell-language-server, which its lsp wants on $PATH).
  # large_pkgs are the big leaves -- desktop apps, anything carrying an
  # electron/qt/webkit runtime, the heavy dev tools -- and only go in on the
  # hosts (!ci). cuda_pkgs are the CUDA builds, see the let at the top.
  home.packages = let
    small_pkgs = with pkgs; [
      # cli
      bc
      bind
      curl
      fdupes
      jq
      yq
      file
      git
      git-lfs
      gzip
      htop
      inetutils
      iperf
      lsof
      lz4
      mosh
      nmap
      p7zip
      parallel
      pari
      psmisc
      pv
      rclone
      rlwrap
      rsync
      fastfetch
      netcat
      speedtest-cli
      sysstat
      tmux
      screen
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
      cloc
      colordiff
      gnumake
      flarectl
      ossutil
      syncplay
      nanokvmctl # NanoKVM power/reset/boot control (warmdarksea/nanokvmctl, via overlays.default)
      # light desktop
      exif
      feh
      ffmpeg
      ffmpegthumbnailer
      file-roller
      flac
      mesa-demos
      keepassxc
      mpv
      pavucontrol
      sshfs-fuse
      trash-cli
      wl-clipboard
      xorg.xclock
      xorg.xev
      xorg.xeyes
      yt-dlp
      flatpak
      flatpak-builder
      # in the closure through programs.emacs anyway
      ghc
      haskell-language-server
    ];
    large_pkgs = with pkgs; [
      # browsers and electron/qt/webkit apps
      chromium
      signal-desktop
      komikku
      foliate
      remmina
      gnome-software
      qbittorrent
      vlc
      wireshark-qt
      # big desktop apps
      libreoffice
      gimp
      krita
      anki
      ghidra
      retroarch-free
      virt-manager
      # heavy dev tools
      awscli2
      cabal-install
      (pkgs.opentofu.withPlugins (p: [
        p.hashicorp_null
        p.hashicorp_tls
        p.dmacvicar_libvirt
        p.hashicorp_aws
        p.hashicorp_azurerm
        p.aliyun_alicloud
      ]))
      # retired / parked: audacity calibre inkscape gzdoom prismlauncher
      # element-desktop evolution okular filezilla hexchat docker
      # docker-compose vscodium qemu ddd gdb ghc-via-emacs terraform.withPlugins
    ];
    # CUDA builds (cycles/optix, nvenc): hours to build, so only with the
    # cache-friendly default cudaCapabilities, never on the runner.
    cuda_pkgs = with pkgs; [
      blender
      obs-studio
    ];
    shell_scripts = [
      # fixme: mktemp_home / random_passwd / random_hex lived in the old
      # gensokyo-dotfiles repo, which is no longer an input. inline the
      # scripts here (bin/) if they're still wanted.
    ];
  in lib.concatLists [
    small_pkgs
    shell_scripts
    (lib.optionals (!ci) large_pkgs)
    (lib.optionals (cudaEnabled && !ci) cuda_pkgs)
  ];

  programs.bash = {
    enable = true;
    
    initExtra = ''
      PROMPT_COMMAND='printf "\e]0;%s@%s: %s\a" "$USER" "$HOSTNAME" "''${PWD/#$HOME/\~}"'
    '';
  };

  # shellAliases = {
  #   example = "true";
  # };

  programs.emacs = {
    enable = true;
    package = pkgs.emacs-pgtk;
    extraPackages = let
      lean4-mode = {
        trivialBuild,
        fetchFromGitHub,
        lean4,
        dash,
        lsp-mode,
        magit-section,
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
      #pkgs.terraform-ls
      pkgs.haskell-language-server
      pkgs.ghc
      pkgs.llvmPackages_19.clang
      pkgs.llvmPackages_19.clang-tools
      epkgs.use-package
      epkgs.forth-mode
      epkgs.go-mode
      epkgs.flycheck
      epkgs.lsp-mode
      epkgs.lsp-ui
      epkgs.lsp-haskell
      epkgs.magit
      epkgs.bison-mode
      epkgs.rust-mode
      epkgs.paredit
      epkgs.geiser
      epkgs.geiser-chez
      epkgs.haskell-mode
      epkgs.neotree
      epkgs.all-the-icons
      epkgs.nix-mode
      epkgs.nix-buffer
      epkgs.gnuplot-mode
      epkgs.yaml-mode
      (epkgs.callPackage lean4-mode {})
      epkgs.terraform-mode
      pkgs.tofu-ls
      epkgs.claude-code
      epkgs.gptel
      epkgs.ibuffer-sidebar
      epkgs.dap-mode
    ];

    # i do not recall what problem this was intended to fix...
    extraConfig = ''
      (add-to-list 'load-path "${./../etc/emacs}")
      (when (not (boundp 'site-lisp-config))
        (setq site-lisp-config "${./../etc/emacs/site-config.el}"))
      (load-file site-lisp-config)
      (load "~/.emacs" t)
    '';
  };

  # programs.neovim = {
  #   enable = true;
  #   plugins = with pkgs.vimPlugins; [
  #     nvim-tree-lua
  #     nvim-web-devicons
  #     nvim-lspconfig
  #     lean-nvim
  #   ];
  #   extraPackages = with pkgs; [ lean4 ];
  # };

  programs.firefox = {
    enable = true;
    policies = {
      Certificates = {
        ImportEnterpriseRoots = true;
      };
    };
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
