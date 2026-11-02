{ config, lib, pkgs, ... }: {
  system.nixos.label = "oci";

  boot.isContainer = lib.mkForce false;

  # ---------- Boot / kernel ----------
  services.cloud-init.enable = true;
}
