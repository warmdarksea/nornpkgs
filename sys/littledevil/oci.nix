{ config, lib, pkgs, ... }: {
  system.nixos.label = "oci";

  boot.isContainer = lib.mkForce false;
  #boot.loader.efi.canTouchEfiVariables = true;
  #networking.useHostResolvConf = false;

  # ---------- Boot / kernel ----------
  # boot.kernelParams = [
  #   "console=ttyS0" # enable serial console
  #   #"console=tty1"
  # ];
  services.cloud-init.enable = true;
  #system.build.OCIImage.memSize = lib.mkDefault 4096;
  # system.build.OCIImage = lib.mkForce (import ./make-disk-image.nix {
  #   inherit config lib pkgs;
  #   inherit (config.virtualisation) diskSize;
  #   name = "oci-image";
  #   configFile = "${nixpkgs}/nixos/modules/virtualisation/oci-config-user.nix";
  #   format = "qcow2";
  #   partitionTableType = "efi";
  #   memSize = 4096;
  # });
}
