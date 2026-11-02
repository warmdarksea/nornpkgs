# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, lib, pkgs, ... }: {
  nixpkgs.config.allowUnfree = true;

  # machine specs live in hw/eeepc.nix

  fileSystems."/" =
    { device = "ember";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = config.gensokyo.disks.boot or "/dev/disk/by-label/eientei-boot";
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

  swapDevices = [ ];

  nix.settings.max-jobs = lib.mkDefault 0;

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
  boot.loader.grub.device = config.gensokyo.disks.grub or "/dev/disk/by-id/eientei-disk";
  boot.loader.grub.splashImage = "/boot/splash.png";

  networking.hostName = "eientei";
  networking.hostId = lib.mkDefault "00000000";
  networking.networkmanager.enable = true;

  networking.interfaces.enp4s0.useDHCP = true;
  time.timeZone = "America/New_York";

  environment.systemPackages = with pkgs; [
    wget emacs-nox
  ];

  services.openssh.enable = true;

  # 2GB of ram; keep the old sound server, not pipewire
  services.pipewire.enable = false;
  services.pulseaudio.enable = true;

  services.xserver.enable = true;
  services.xserver.exportConfiguration = true;
  services.xserver.xkb.layout = "us";
  services.xserver.windowManager.dwm.enable = true;
  services.xserver.displayManager.lightdm.enable = true;
  services.libinput.enable = true;

  fonts = {
    enableDefaultPackages = false;
    packages = with pkgs; [
      xorg.fontbh100dpi
      xorg.fontmiscmisc
      xorg.fontcursormisc
      ubuntu-classic
      liberation_ttf
      terminus_font
      proggyfonts
      unifont
    ];
    fontconfig = {
      hinting.autohint = false;
      useEmbeddedBitmaps = true;
      defaultFonts.serif = [ "Liberation Serif" "Times New Roman" ];
      defaultFonts.sansSerif = [ "Liberation Sans" "Arial" "Ubuntu" ];
      defaultFonts.monospace = [ "Ubuntu Mono" ];
    };
  };

  users.users.kaguya = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ]; # Enable ‘sudo’ for the user.
  };
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "20.09"; # Did you read the comment?

}
