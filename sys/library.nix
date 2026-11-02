{ config, lib, pkgs, ... }: {
  nixpkgs.config.allowUnfreePredicate = pkg: (builtins.elem (lib.getName pkg) [
    "corefonts"
    "nvidia-x11"
    "nvidia-persistenced"
    "nvidia-settings"
    "cudnn"
    "vcv-rack"
  ]) || (builtins.all (license:
    license.free || builtins.elem license.shortName [
      "CUDA EULA"
      "NVidia OptiX EULA"
    ]
  ) (if builtins.isList pkg.meta.license then pkg.meta.license else [ pkg.meta.license ]));

  nix.settings.keep-failed = true;
  nixpkgs.config.allowUnfree = true;

  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  boot.loader.efi.canTouchEfiVariables = true;

  # --- UEFI BootOrder pinning -----------------------------------------------
  # Windows Boot Manager promotes itself to the head of BootOrder on every boot,
  # demoting the NanoKVM entry so the uefi_trampoline never gets booted. No OS
  # can lock BootOrder, so both sides re-assert it: this unit on start *and*
  # stop, and lib/boot-order-assert.ps1 as a startup task on the Windows side.
  # Rationale and the by-label resolution live in the script's header comment.
  systemd.services.assert-boot-order =
    let
      pin = pkgs.writeShellApplication {
        name = "boot-order-assert";
        runtimeInputs = with pkgs; [ efibootmgr gawk gnused gnugrep coreutils ];
        text = builtins.readFile ../lib/boot-order-assert.sh;
      };
    in {
      description = "Pin UEFI BootOrder with the NanoKVM entry first";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      unitConfig.ConditionPathExists = "/sys/firmware/efi/efivars";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;            # so ExecStop fires on shutdown too
        ExecStart = "${pin}/bin/boot-order-assert";
        ExecStop = "${pin}/bin/boot-order-assert";
      };
    };

  # machine specs live in hw/library.nix

  boot.zfs.requestEncryptionCredentials = false;

  fileSystems."/" = {
    device = "story";
    fsType = "zfs";
  };
  
  fileSystems."/nix" = {
    device = "story/nix";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = config.gensokyo.disks.boot or "/dev/disk/by-partlabel/library-boot";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  boot.initrd.network = {
    enable = true;
    ssh = {
      # the authorized keys come from gensokyo-private, which the ci stub
      # does not have, and initrd ssh will not evaluate without one
      enable = !config.gensokyo.ci;
      port = 2222;  # different port so your normal known_hosts entry doesn't conflict
      # the real key path lives in gensokyo-private.nixosModules.library; this
      # placeholder only keeps the public/ci stubs evaluating (it is a string
      # the initrd reads at build time, so nothing touches it at eval)
      hostKeys = lib.mkDefault [ "/var/secret/initrd/ssh_host_ed25519_key" ];
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  swapDevices = [ ];
  
  networking.useDHCP = lib.mkDefault true;

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
  security.auditd.enable = true;
  security.audit.enable = true;
  security.auditd.plugins = {
    syslog = {
      path = lib.getExe' config.security.auditd.package "audisp-syslog";
      args = [ "LOG_INFO" ];
    };
  };
  security.audit.rules = [
    "-a always,exit -F arch=b64 -S execve -F uid=${builtins.toString config.users.users.claude.uid} -k claude-exec"
  ];

  programs.nix-required-mounts = {
    enable = true;
    presets.nvidia-gpu.enable = true;
  };

  environment.systemPackages = with pkgs; [
    dtach
    efibootmgr
    sbctl
  ];

  system.stateVersion = "26.11";
}
