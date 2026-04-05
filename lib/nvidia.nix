{ config, lib, pkgs, ... }:

let
  nvidiaPkgNames = [
    "nvidia-x11"
    "nvidia-persistenced"
    "nvidia-settings"
    "cudnn"
    #    "cuda_cudart"
    #    "cuda_cccl"
    #    "libcublas"
    #    "nvtop"
  ];
  nvidiaLicenses = [
    "CUDA EULA"
    #    "cuDNN EULA"
    #    "cuTENSOR EULA"
    "NVidia OptiX EULA"
  ];
in {
  # nixpkgs.config = {
  #   cudaSupport = true;

  #   # allowUnfreePredicate = _: true;

  #   allowUnfreePredicate = let
  #     nvidiaNamePred = pkg: (builtins.elem (lib.getName pkg) nvidiaPkgNames);
  #     nvidiaLicensePred = pkg: let
  #       pkgLicenses = if builtins.isList pkg.meta.license
  #                     then pkg.meta.license
  #                     else [ pkg.meta.license ];
  #     in builtins.all (license:
  #       license.free || builtins.elem license.shortName nvidiaLicenses) pkgLicenses;
  #   in pkg: (nvidiaNamePred pkg) || (nvidiaLicensePred pkg);
  # };

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead 
    # of just the bare essentials.
    powerManagement.enable = true;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = true;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of 
    # supported GPUs is at: 
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus 
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = true;

    #package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  #boot.extraModulePackages = with pkgs; [ linuxKernel.packages.nvidia_x11 ];
  # boot.extraModulePackages = with config.boot.kernelPackages; [ hardware.nvidia.package ];
  boot.blacklistedKernelModules = [ "nouveau" ];

  hardware.nvidia.prime = {
    offload = {
      enable = true;
      enableOffloadCmd = true;
    };
    # Make sure to use the correct Bus ID values for your system!
    # amdgpuBusId = "PCI:1:0:0"; # For AMD GPU
    # intelBusId = "PCI:0:2:0";
    # nvidiaBusId = "PCI:105:0:0";
  };
}
