{ config, pkgs, lib, ... }: {
  # lets us build this derivation standalone, with no bootloader
  boot.isContainer = lib.mkDefault true;

  # ssh, the firewall and the root key live in lib/server.nix, which is
  # included next to this module in every littledevil configuration

  networking.firewall.allowedTCPPorts = [ 22 ];

  #environment.systemPackages = with pkgs; [
  #  tcpdump
  #];

  system.stateVersion = "24.11";
}
