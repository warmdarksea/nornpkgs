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

  # the zfs storage driver and its dataset live in inst/, the nvidia runtime in hw/
  virtualisation.docker.enable = true;

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

  # the gpu for nix builds. the preset drags mesa and llvm in (1.8 GB) for a
  # runner VM that has no gpu, so it follows gensokyo.ci like cudaSupport
  programs.nix-required-mounts = {
    enable = !config.gensokyo.ci;
    presets.nvidia-gpu.enable = true;
  };

  # slopbooru's fleet, one model at a time on the 3090, behind the OpenAI
  # API on 127.0.0.1:8100. A token: sudo -u gpu-timeshare gpu-timeshare-admin
  # token add NAME. The weights (~75 GB) are in the system closure.
  services.gpu-timeshare = {
    enable = true;
    inherit (pkgs.slopbooru-fleet) models settings;
  };

  environment.systemPackages = with pkgs; [
    dtach
    efibootmgr
    sbctl
  ];
}
