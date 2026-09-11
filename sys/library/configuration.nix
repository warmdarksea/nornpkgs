{ config, lib, pkgs, ... }: {
  imports = [
  ];

  nixpkgs.config.allowUnfreePredicate = pkg: (builtins.elem (lib.getName pkg) [
    "corefonts"
    "nvidia-x11"
    "nvidia-persistenced"
    "nvidia-settings"
    "cudnn"
    #    "cuda_cudart"
    #    "cuda_cccl"
    #    "libcublas"
    #    "nvtop"
    "vcv-rack"
  ]) || (builtins.all (license:
    license.free || builtins.elem license.shortName [
      "CUDA EULA"
      #    "cuDNN EULA"
      #    "cuTENSOR EULA"
      "NVidia OptiX EULA"
    ]
  ) (if builtins.isList pkg.meta.license then pkg.meta.license else [ pkg.meta.license ]));

  nix.settings.keep-failed = true;
  nixpkgs.config.allowUnfree = true;

  # Lanzaboote currently replaces the systemd-boot module.
  # This setting is usually set to true in configuration.nix
  # generated at installation time. So we force it to false
  # for now.
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [ "vmd" "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "mlx5_core" ];
  boot.initrd.kernelModules = [ "kvm-intel" ];

  boot.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
  boot.blacklistedKernelModules = [ "nouveau" ];
  boot.extraModulePackages = [ ];
  boot.zfs.requestEncryptionCredentials = false;

  fileSystems."/" =
    { device = "story";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    { device = "story/nix";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = config.gensokyo.disks.boot or "/dev/disk/by-partlabel/library-boot";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;  # different port so your normal known_hosts entry doesn't conflict
      hostKeys = [ /var/secret/ssh_library_ed25519_key ];
      authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted" ];
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted"
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  hardware.nvidia.nvidiaPersistenced = true;

  swapDevices = [ ];
  
  networking.useDHCP = lib.mkDefault true;
  #networking.dhcpcd.enable = false;
  #networking.interfaces.enp6s0.ipv4.addresses = [
  #  { address = "0.0.0.0"; prefixLength = 24; }
  #];
  #networking.defaultGateway = "0.0.0.0";
  #networking.nameservers = ["0.0.0.0"];

  virtualisation.docker = {
    enable = true;
    enableNvidia = true;

    # overlayfs backed by zfs is broken, you need to use zfs proper for it to work
    storageDriver = "zfs";
    daemon.settings = {
      storage-opts = [ "zfs.fsname=story/docker" ];
    };
  };

  users.users.patchouli = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
  };

  environment.systemPackages = with pkgs; [
    dtach
    efibootmgr
    sbctl
  ];

  hardware.opengl = {
    enable = true;
    #driSupport = true;
    driSupport32Bit = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];

  hardware.graphics.enable = true;
  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = true;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of 
    # supported GPUs is at: 
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus 
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = true;

    # Enable the Nvidia settings menu,
	  # accessible via `nvidia-settings`.
    nvidiaSettings = false;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    # package = config.boot.kernelPackages.nvidiaPackages;
    #package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  hardware.enableRedistributableFirmware = true;

  #system.copySystemConfiguration = true;

  #system.stateVersion = "23.05"; # Did you read the comment?
  system.stateVersion = "26.11"; # Did you read the comment?
}
