# NixOS module: unlock FP/BF16 issue rate on RTX 3000-series (GA102/3/4/6)
# cards before the nvidia driver binds them. Exposed from the flake as
# nixosModules.nvidia_3090_unlock. The packaging it builds on (source pin,
# firmware, kernel module) lives in hw/nvidia_3090_unlock.nix.
#
# It wires up three things:
#   * the gpu_unlock kernel module (boot.extraModulePackages),
#   * its generated firmware (hardware.firmware), and
#   * early loading in the initrd, before nvidia, plus the opt-in kernel
#     command line the module requires to do anything.
#
# The module declares MODULE_FIRMWARE() for all five payload files, so once the
# firmware package is in hardware.firmware and gpu_unlock is in the initrd,
# makeModulesClosure copies exactly those files into the initramfs for us.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.nvidia-3090-unlock;

  gpuUnlock = pkgs.callPackage ../hw/nvidia_3090_unlock.nix { };
  kernelModule = gpuUnlock.moduleFor config.boot.kernelPackages.kernel;

  targetsParam =
    lib.optional (cfg.targets != [ ])
      "gpu_unlock.targets=${lib.concatStringsSep "," cfg.targets}";
  resumeParam = lib.optional (!cfg.resume) "gpu_unlock.resume=0";
in
{
  options.hardware.nvidia-3090-unlock = {
    enable = lib.mkEnableOption ''
      the gpu-unlock kernel module, which doubles the FP/BF16 FMA issue rate on
      GA102/GA103/GA104/GA106 cards by running an unlock before the nvidia
      driver binds them. x86_64 only
    '';

    targets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "all" ];
      example = [ "0000:21:00.0" "0000:22:00.0" ];
      description = ''
        Which cards to unlock, passed as `gpu_unlock.targets=`. Use the single
        entry `"all"` for every unbound GA102/3/4/6 card, or a list of full PCI
        addresses as `lspci -D` prints them. An empty list loads the module but
        unlocks nothing (the kernel command line opt-in is omitted).
      '';
    };

    resume = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Re-run the unlock on resume from suspend-to-RAM, which otherwise resets
        the speed selectors. Set to false to append `gpu_unlock.resume=0`.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = kernelModule;
      defaultText = lib.literalMD "the gpu_unlock module built against `boot.kernelPackages.kernel`";
      description = "The gpu_unlock kernel-module package.";
    };

    firmwarePackage = lib.mkOption {
      type = lib.types.package;
      default = gpuUnlock.firmware;
      defaultText = lib.literalMD "the generated pinned 610.43.03 firmware";
      description = "The generated firmware package the module loads.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isx86_64;
        message = "hardware.nvidia-3090-unlock only supports x86_64-linux.";
      }
    ];

    boot.extraModulePackages = [ cfg.package ];
    hardware.firmware = [ cfg.firmwarePackage ];

    # Load in the initrd and ahead of nvidia, so the unlock finishes before the
    # driver can bind a card. mkBefore keeps it first if nvidia is also an
    # initrd module (early KMS); if nvidia loads in stage 2 it is first anyway.
    boot.initrd.kernelModules = lib.mkBefore [ "gpu_unlock" ];

    boot.kernelParams = targetsParam ++ resumeParam;
  };
}
