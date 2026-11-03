{ config, lib, pkgs, ... }:

{
  # Set from the gensokyo-private input by nixosModules.base in flake.nix:
  # the `ci` branch of gensokyo-private exports `gensokyo.ci = true`, the
  # public stub and the private branch export nothing. Modules that would
  # drag an hours-long build into the closure (the CUDA group in
  # home/common.nix) check this and leave it out on the runner.
  options.gensokyo.ci = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "building on the CI runner (gensokyo-private's ci branch): skip what a runner cannot build";
  };

  # What the runner's VM cannot use at all, cut across every host: the
  # 32-bit graphics and audio stacks (a second mesa, llvm and driver, 1.5 GB)
  # and speech-dispatcher, which the graphical desktop turns on by default
  # and which brings the mbrola voices (0.7 GB).
  config = lib.mkIf config.gensokyo.ci {
    hardware.graphics.enable32Bit = lib.mkForce false;
    services.pipewire.alsa.support32Bit = lib.mkForce false;
    # the deprecated docker option (hw/library.nix) asserts 32-bit support
    virtualisation.docker.enableNvidia = lib.mkForce false;
    services.speechd.enable = lib.mkForce false;
  };
}
