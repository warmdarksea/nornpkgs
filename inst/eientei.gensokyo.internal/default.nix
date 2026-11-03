{ config, lib, pkgs, ... }: {
  networking.hostName = "eientei";
  networking.hostId = lib.mkDefault "00000000";

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

  networking.interfaces.enp4s0.useDHCP = true;

  system.stateVersion = "20.09";
}
