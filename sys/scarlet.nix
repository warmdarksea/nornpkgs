import <nixpkgs/nixos> {
  system = "x86_64-linux";
  configuration = { config, lib, pkgs, modulesPath, ... }: {
    imports = [
      ../profile/base.nix
      ../hw/lenovo_thinkpad_x230t.nix
      ../profile/laptop.nix
      ../profile/x11.nix
      ../profile/dev.nix
      ../session/icewm.nix
    ];

    fileSystems."/" = {
      device = "/dev/disk/by-uuid/REDACTED";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/REDACTED";
      fsType = "ext4";
    };

    boot.initrd.luks.devices."hark".device = "/dev/disk/by-uuid/REDACTED";

    swapDevices = [ ];

    boot.loader.grub.enable = true;
    boot.loader.grub.version = 2;
    boot.loader.grub.device = "/dev/disk/by-id/REDACTED";
    #  boot.loader.grub.splashImage = "/boot/splash.png";

#  hardware.cpu.intel.updateMicrocode = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  #boot.kernelParams = ["boot.shell_on_fail"];
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

#  security.rngd.enable = false;

  networking.hostId = "AAAAAAAA";
  networking.hostName = "scarlet";
  services.nscd.enable = true;

  nixpkgs.config.allowUnfree = true;

  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.qemuVerbatimConfig = ''
    dynamic_ownership = 0
  '';

  services.xserver.displayManager.autoLogin = {
    user = "remilia";
    enable = true;
  };

  services.xserver.enable = true;
  #services.xserver.displayManager.defaultSession = lib.mkForce "deepin";
  #services.xserver.displayManager.gdm.enable = true;
  #services.xserver.desktopManager.gnome.enable = true;
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;
  services.xserver.desktopManager.plasma5.mobile.enable = true;
  services.xserver.desktopManager.plasma5.mobile.installRecommendedSoftware = true;
  # services.xserver.desktopManager.cinnamon.enable = true;
  # services.xserver.desktopManager.deepin.enable = true;
  # services.xserver.desktopManager.mate.enable = true;
  # services.xserver.desktopManager.phosh.enable = true;


  #virtualisation.libvirtd.enable = true;
  #virtualisation.libvirtd.qemuVerbatimConfig = ''
  #  dynamic_ownership = 0
  #'';
#  virtualisation.lxd.enable = true;
#  virtualisation.docker.enable = true;

  # containers.vidya = {
  #   config = import ./containers/vidya.nix;
  #   bindMounts = {
  #     # xorg
  #     "/tmp/.X11-unix/X1" = {
  #       hostPath = "/tmp/.X11-unix/X1";
  #       isReadOnly = true;
  #     };
  #     # pulseaudio
  #     "/run/pulse" = {
  #        hostPath = "/run/pulse";
  #        isReadOnly = true;
  #     };
  #     "/mnt/vidya" = {
  #       hostPath = "/mnt/vidya";
  #       isReadOnly = false;
  #     };
  #     "/mnt/steam/argent" = {
  #       hostPath = "/mnt/steam/argent";
  #       isReadOnly = false;
  #     };
  #     "/mnt/steam/viridian" = {
  #       hostPath = "/mnt/steam/viridian";
  #       isReadOnly = false;
  #     };
  #   };
  # };

  #hardware.pulseaudio.enable = true;
  #hardware.pulseaudio.package = pkgs.pulseaudioFull;
  #hardware.pulseaudio.daemon.config = { flat-volumes = "no"; };
  #hardware.pulseaudio.systemWide = true;
  #hardware.pulseaudio.support32Bit = true;

  #services.dbus.enable = true;
#  services.physlock.enable = true;

#   fonts = {
#     fonts = with pkgs; [
#       powerline-fonts
#       ipafont
#       baekmuk-ttf
#       source-han-sans-japanese
# #      kochi-substitute
#       carlito
#     ];

#     fontconfig = { 
#       defaultFonts = {
#         monospace = [ 
#           "DejaVu Sans Mono for Powerline"
#           "IPAGothic"
#           "Baekmuk Dotum"
#         ];
#         serif = [ 
#           "DejaVu Serif"
#           "IPAPMincho"
#           "Baekmuk Batang"
#         ];
#         sansSerif = [
#           "DejaVu Sans"
#           "IPAPGothic"
#           "Baekmuk Dotum"
#         ];
#       };
#     };
#   };

  programs = {
#    ibus.enable = true;
    adb.enable = true;
  };

  #i18n.inputMethod.ibus.engines = [ pkgs.ibus-anthy pkgs.mozc ];

  users.extraUsers.remilia = {
     description = "Remilia Scarlet";
    isNormalUser = true;
    uid = 1000;
    extraGroups = ["wheel" "audio" "video" "pulse" "lxd" "libvirtd" "docker" "adbusers" "networkmanager"];
  };

  environment.systemPackages = with pkgs;
                                                   [awesome rxvt_unicode xfce.tumbler psmisc iptables zfs qemu xf86_input_wacom wireguard-tools plymouth icewm];
#  systemd.services.lxd.path = [ pkgs.zfs ];
#  nixpkgs.config.packageOverrides = super: let self = super.pkgs; in {
#    mumble = super.mumble.override { pulseSupport = true; };
#  };

  environment.etc."fuse.conf" = { text = ''
    user_allow_other
  '';};

  system.stateVersion = "21.05"; # Did you read the comment?
 };
}