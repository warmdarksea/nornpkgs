{config, lib, pkgs, ...}:

{
  nix.settings.auto-optimise-store = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowlistedLicenses = with lib.licenses; [ bsl11 ];

  systemd.services.nixos-upgrade.path = [ pkgs.git ];

  boot.kernelParams = ["boot.shell_on_fail" "console=tty1"];

  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
  };

  time.timeZone = "America/New_York";

  networking.domain = "gensokyo.internal";

  services.resolved.enable = true;
  #services.resolved.extraConfig = ''
  #[Resolve]
  #DNS=0.0.0.0
  #Domains=~gensokyo.internal
  #'';
  services.resolved.settings.Resolve.DNS = [ "0.0.0.0" ];
  services.resolved.settings.Resolve.Domains = [ "~gensokyo.internal" ];

  security.pki.certificateFiles = [
    ../etc/certs/gensokyo.internal.ca.pem
  ];

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  documentation.dev.enable = true;
  documentation.man.generateCaches = true;

  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
    gnumake
    man-pages
    man-pages-posix
    tmux
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
  };

  # systemd.services.setconsole = {
  #   script = ''
  #     ${pkgs.busybox}/bin/setconsole /dev/tty1
  #   '';
  #   wantedBy = [ "multi-user.target" ];
  # };
}
