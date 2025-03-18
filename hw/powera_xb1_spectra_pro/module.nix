{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.hardware.powera_xb1_spectrapro;
  powera_xb1_spectrapro_pkg = with pkgs; pkgs.lib.callPackageWith pkgs ./default.nix { inherit linuxConsoleTools; };
in {
  options.hardware.powera_xb1_spectrapro = {
    enable = mkEnableOption "Enable udev rules to automatically calibrate/map a PowerA XB1 Spectra Pro controller.";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ powera_xb1_spectrapro_pkg pkgs.linuxConsoleTools ];

    services.udev.packages = [ powera_xb1_spectrapro_pkg ];
  };
}
