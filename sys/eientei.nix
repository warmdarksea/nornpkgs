# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

import <nixpkgs/nixos> {
  system = "i686-linux";
  configuration = let
    localpkgs = import <localpkgs> { };
  in { config, lib, pkgs, ... }: {
    imports = [
#      /cfg/base.nix
#      /cfg/opt/crypt.nix
      ../profile/base.nix
      ../module/crypt.nix
    ];

    nixpkgs.config.allowUnfree = true;

    boot.initrd.availableKernelModules = [ "uhci_hcd" "ehci_pci" "ata_piix" "usb_storage" "sd_mod" "adiantum" "chacha_generic" "poly1305_generic" "nhpoly1305" ];
    boot.initrd.kernelModules = [ "loop" ];
    boot.kernelModules = [  ];
    boot.extraModulePackages = [ ];
    boot.kernelParams = ["boot.shell_on_fail" "ramdisk_size=64000" "zfs_prefetch_disable=1" "zfs_nocacheflush=1" "vmalloc=512M"];
    #  boot.kernelPackages = pkgs.linuxPackages_latest;
    boot.zfs.enableUnstable = true;
    #hardware.enableAllFirmware = true;
    hardware.enableRedistributableFirmware = true;

    fileSystems."/" =
      { device = "ember";
        fsType = "zfs";
      };

    fileSystems."/boot" =
      { device = "/dev/disk/by-uuid/REDACTED";
        fsType = "ext4";
      };

    fileSystems."/nix" =
      { device = "ember/nix";
        fsType = "zfs";
      };

    fileSystems."/home" =
      { device = "ember/home";
        fsType = "zfs";
      };

    # boot.crypt = {
    #   enable = true;
    #   initramfs = "/boot/header.gz";
    #   header = "/eientei.h";
    #   image = "/eientei.img";
    #   image_type = "ext4";
    #   devices = ["ember0"];
    #   pools = ["ember"];
    #   root = "ember";
    #   root_type = "zfs";
    # };

    boot.crypt = {
      enable = true;
      initramfs = "/boot/header.gz";
      header = "/boot/eientei.h";
      image = "/boot/eientei.img";
      image_type = "ext4";
      devices = ["ember0"];
      pools = ["ember"];
      root = "ember";
      root_type = "zfs";
    };

    swapDevices = [ ];

    nix.maxJobs = lib.mkDefault 0;

    nix.buildMachines = [
      {
	      hostName = "forest.of.magic";
	      systems = ["x86_64-linux" "i686-linux"];
	      supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
	      mandatoryFeatures = [ ];
	    }
    ];
	  nix.distributedBuilds = true;
	  # optional, useful when the builder has a faster internet connection than yours
	  nix.extraOptions = ''
		builders-use-substitutes = true
	'';

    # Use the GRUB 2 boot loader.
    boot.loader.grub.enable = true;
    boot.loader.grub.version = 2;
    #  boot.loader.grub.device = "/dev/disk/by-id/REDACTED";
    boot.loader.grub.device = "/dev/disk/by-id/REDACTED";
    boot.loader.grub.splashImage = "/boot/splash.png";

    networking.hostName = "eientei";
    networking.hostId = "AAAAAAAA";
    networking.networkmanager.enable = true;

    networking.interfaces.enp4s0.useDHCP = true;
    time.timeZone = "America/New_York";

    environment.systemPackages = with pkgs; [
      wget emacs-nox
    ];

    services.openssh.enable = true;

    sound.enable = true;
    hardware.pulseaudio.enable = true;

    services.xserver.enable = true;
    services.xserver.exportConfiguration = true;
    services.xserver.videoDrivers = ["intel"];
    services.xserver.layout = "us";
    services.xserver.windowManager.dwm.enable = true;
    services.xserver.displayManager.lightdm.enable = true;
    services.xserver.libinput.enable = true;

    fonts = {
      enableDefaultFonts = false;
      fonts = with pkgs; [
        xorg.fontbh100dpi
        xorg.fontmiscmisc
        xorg.fontcursormisc
        ubuntu_font_family
        liberation_ttf
        terminus_font
        proggyfonts
        unifont
      ];
      fontconfig = {
        hinting.autohint = false;
        #      penultimate.enable = false;
        useEmbeddedBitmaps = true;
        defaultFonts.serif = [ "Liberation Serif" "Times New Roman" ];
        defaultFonts.sansSerif = [ "Liberation Sans" "Arial" "Ubuntu" ];
        defaultFonts.monospace = [ "Ubuntu Mono" ];
      };
    };

    # nixpkgs.config =
    #   {
    #     packageOverrides = super:
    #       let
    #         self = super.pkgs;
    #       in {
    #         dwm = localpkgs.dwm;
    #       };
    #   };

    users.users.kaguya = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" ]; # Enable ‘sudo’ for the user.
    };

    nix.autoOptimiseStore = true;
    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    system.stateVersion = "20.09"; # Did you read the comment?

  };
}