{ config, lib, pkgs, ... }:

{
  # logical disk name -> device path. public host configs reference
  # config.gensokyo.disks.<name> (with a by-label fallback so the public
  # stub still evaluates); the real /dev/disk/by-* paths live in the
  # per-host modules of gensokyo-private.
  options.gensokyo.disks = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = { boot = "/dev/disk/by-uuid/4E21-19F3"; };
    description = "mapping from logical disk names to device paths";
  };
}
