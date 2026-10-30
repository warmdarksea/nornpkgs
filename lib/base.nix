{config, lib, pkgs, ...}:

{
  imports = [ ./disks.nix ./ci.nix ];

  nix.settings.auto-optimise-store = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # cache.nixos.org plus the nixpkgs CUDA team's cache (the nixConfig block in
  # flake.nix has the story). Defining these lists replaces the module
  # defaults, so cache.nixos.org is spelled out again. nix asks the caches in
  # ascending priority (cache.nixos.org advertises 40), so the CUDA cache is
  # pinned behind it: anything hydra built comes from cache.nixos.org, and the
  # CUDA cache only ever serves what cache.nixos.org does not have.
  nix.settings.substituters = [
    "https://cache.nixos.org/"
    "https://cache.nixos-cuda.org?priority=50"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
  ];

  #nixpkgs.config.allowlistedLicenses = with lib.licenses; [ bsl11 ];

  systemd.services.nixos-upgrade.path = [ pkgs.git ];

  boot.kernelParams = ["boot.shell_on_fail" "console=tty1"];

  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
  };

  time.timeZone = lib.mkDefault "America/New_York";

  networking.domain = "gensokyo.internal";

  services.resolved = {
    enable = true;

    llmnr = "false";

    #services.resolved.extraConfig = ''
    #[Resolve]
    #DNS=0.0.0.0
    #Domains=~gensokyo.internal
    #'';

    settings.Resolve.DNS = [ "10.217.37.1" ];
    settings.Resolve.Domains = [ "~gensokyo.internal" ];
  };

  #security.pki.certificateFiles = [
  #  ../etc/certs/gensokyo.internal.ca.pem
  #];

  #environment.etc."pki/ca-trust/source/anchors/gensokyo.internal.ca.pem".source = ../etc/certs/gensokyo.internal.ca.pem;

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  # mkDefault so the installer images (which force "no") don't conflict
  services.openssh.settings.PermitRootLogin = lib.mkDefault "prohibit-password";

  # dev docs pull every package's doc/devdoc output into the closure (nix's
  # doxygen tree alone is an uncached build), and the man cache is a mandb
  # run over all of them. Neither is worth the runner's time.
  documentation.dev.enable = !config.gensokyo.ci;
  documentation.man.cache.enable = !config.gensokyo.ci;

  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
    gnumake
    man-pages
    man-pages-posix
    tmux
    ripgrep # fast recursive grep (`rg`)
    lshw
    pciutils
    usbutils
    htop
    btop
    nix-du
    nix-index
    nix-prefetch-scripts
    nix-tree
    nmap
    fastfetch
    tpm2-tools
    gptfdisk
    e2fsprogs
  ];

  console = let 
    inherit (pkgs) lib stdenv writeText kbd;
    mykeymap = writeText "keymap" ''
      include "${kbd}/share/keymaps/i386/qwerty/us.map.gz"

      # thank you to whatever wizard wrote https://www.emacswiki.org/emacs/LinuxConsoleKeys#h5o-1
      # This turns CapsLK into Control. Include if you don't want that.
      keycode  58 = Control      
          
      # Binds S-<tab>, useful for global visibility cykling in org
      keycode  15 = Tab             
       	shift	keycode  15 = F36
    
      # Binds C-/S-/C-S-/M-/M-S-<return>
      keycode  28 = Return          
      	control	keycode  28 = F13  
      	shift	keycode  28 = F37           
      	shift	control	keycode  28 = F14       
      	alt	keycode  28 = Meta_Control_m  
      	shift	alt	keycode  28 = F15  
          
      # Binds C-/M-/S-C-S/M-S-<up>
      keycode 103 = Up
      	control	keycode 103 = F26
      	alt	keycode 103 = F22
        shift	keycode 103 = F30
      	control shift	keycode 103 = F34
      	alt	shift	keycode 103 = F18  
          
      # Binds C-/M-/S-C-S/M-S-<left>
      keycode 105 = Left
      	control	keycode 105 = F24
      	alt	keycode 105 = F20
        shift	keycode 105 = F28
      	control shift	keycode 105 = F32
      	alt	shift	keycode 105 = F16
          
      # Binds C-/M-/S-C-S/M-S-<right>
      keycode 106 = Right           
      	control	keycode 106 = F25
      	alt	keycode 106 = F21
        shift	keycode 106 = F29
      	control shift	keycode 106 = F33
      	alt	shift	keycode 106 = F17   
          
          
      # Binds C-/M-/S-C-S/M-S-<down>
      keycode 108 = Down            
      	control	keycode 108 = F27
      	alt	keycode 108 = F23
        shift	keycode 108 = F31
      	control shift	keycode 108 = F35
      	alt	shift	keycode 108 = F19  
          
      # We now need to define a string for all the F-keys we've used plus a few more, just in cause.
      # F13-20 should be defined like this in the default keymap. They are added here for completeness.
      string F13 = "\033[25~"
      string F14 = "\033[26~"
      string F15 = "\033[28~"
      string F16 = "\033[29~"
      string F17 = "\033[31~"
      string F18 = "\033[32~"
      string F19 = "\033[33~"
      string F20 = "\033[34~"
      string F21 = "\033[35~"
      string F22 = "\033[36~"
      string F23 = "\033[37~"
      string F24 = "\033[38~"
      string F25 = "\033[39~"
      string F26 = "\033[40~"
      string F27 = "\033[41~"
      string F28 = "\033[42~"
      string F29 = "\033[43~"
      string F30 = "\033[44~"
      string F31 = "\033[45~"
      string F32 = "\033[46~"
      string F33 = "\033[47~"
      string F34 = "\033[48~"
      string F35 = "\033[49~"
      string F36 = "\033[50~"
      string F37 = "\033[51~"
      string F38 = "\033[52~"
      string F39 = "\033[53~"
      string F40 = "\033[54~"
  '';
  in {
    enable = true;
    earlySetup = true;
    keyMap = "${mykeymap}";
    font = "default8x16";
  };

  # systemd.services.setconsole = {
  #   script = ''
  #     ${pkgs.busybox}/bin/setconsole /dev/tty1
  #   '';
  #   wantedBy = [ "multi-user.target" ];
  # };
}
