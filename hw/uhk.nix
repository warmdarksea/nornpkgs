{ config, lib, pkgs, modulesPath, ... }:

{    
  services.udev.extraRules = ''
    # Ultimate Hacking Keyboard rules
    # These are the udev rules for accessing the USB interfaces of the UHK as non-root users.
    # Copy this file to /etc/udev/rules.d and physically reconnect the UHK afterwards.
    SUBSYSTEM=="input", ATTRS{idVendor}=="1d50", GROUP="input", MODE="0660"
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="1d50", TAG+="uaccess" MODE="0660", GROUP="input"
    KERNEL=="hidraw*", ATTRS{idVendor}=="1d50", TAG+="uaccess" MODE="0660", GROUP="input"
  '';
}