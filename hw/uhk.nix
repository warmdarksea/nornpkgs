{ config, lib, pkgs, modulesPath, ... }:

{    
  services.udev.extraRules = ''
    # Ultimate Hacking Keyboard rules
    SUBSYSTEM=="input", ATTRS{idVendor}=="1d50", GROUP="input", MODE="0660"
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="1d50", TAG+="uaccess" MODE="0660", GROUP="input"
    KERNEL=="hidraw*", ATTRS{idVendor}=="1d50", TAG+="uaccess" MODE="0660", GROUP="input"
  '';
}