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
	nix.extraOptions = ''
		builders-use-substitutes = true
	'';

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
    extraGroups = [ "wheel" "networkmanager" ];
  };
  system.stateVersion = "20.09";

}
