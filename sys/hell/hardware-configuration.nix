{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

 boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" "usbhid" "usb_storage" "sd_mod" "sdhci_pci" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];
  
  boot.initrd.luks.devices.cryptstorage.device =
    config.gensokyo.disks.cryptstorage or "/dev/disk/by-label/hell-cryptstorage";

  boot.zfs.requestEncryptionCredentials = false;

  fileSystems."/" =
    { device = "bell";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = config.gensokyo.disks.boot or "/dev/disk/by-label/HELL_BOOT";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  fileSystems."/gnu" =
    { device = "bell/gnu";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    { device = "bell/nix";
      fsType = "zfs";
    };

  fileSystems."/home" =
    { device = "bell/home";
      fsType = "zfs";
      options = [ "nofail" ];
    };


  fileSystems."/home/clownpiece" =
    { device = "bell/home/clownpiece";
      fsType = "zfs";
      options = [ "nofail" ];
    };

  fileSystems."/home/clownpiece/.cache" =
    { device = "bell/home/clownpiece/cache";
      fsType = "zfs";
      options = [ "nofail" ];
    };

  fileSystems."/home/clownpiece/Pictures/hydrus" =
    { device = "bell/home/clownpiece/hydrus";
      fsType = "zfs";
      options = [ "noauto" "nofail" ];
    };

  fileSystems."/home/clownpiece/.local/secrets" =
    { device = "bell/home/clownpiece/secrets";
      fsType = "zfs";
      options = [ "nofail" ];
    };

  fileSystems."/home/clownpiece/.local/opt/steamapps" =
    { device = "bell/home/clownpiece/steamapps";
      fsType = "zfs";
      options = [ "nofail" ];
    };

  # bell/userdata is ZFS-managed, so not recorded here.

    swapDevices = [
      {
        device = config.gensokyo.disks.swap or "/dev/disk/by-partlabel/hell-swap";
        randomEncryption = {
          enable = true;
          cipher = "aes-xts-plain64";
          keySize = 256;
          allowDiscards = true;  # Optional, for SSDs
        };
      }
    ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp107s0f4u1u4.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp6s0.useDHCP = lib.mkDefault true;
  #networking.wireless.enable = lib.mkForce false;
  #networking.networkmanager.enable = true;
  #networking.hostId = "AAAAAAAA";

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

}
