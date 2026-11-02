{ config, lib, pkgs, ... }: {
  system.nixos.label = "oci";

  boot.isContainer = lib.mkForce false;

  services.cloud-init.enable = true;
}
