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
}
