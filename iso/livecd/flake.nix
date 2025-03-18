{
  description = "A bootable GNOME LiveUSB system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in
  {
    nixosConfigurations.iso-livecd = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ({ config, lib, pkgs, ... }: {
          imports = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-gnome.nix"
          ];

          # Add additional configurations here
          services.xserver = {
            enable = true;
            displayManager.gdm.enable = true;
            desktopManager.gnome.enable = true;
          };

          # Include some useful packages for the live environment
          environment.systemPackages = with pkgs; [
            firefox
            gnome-terminal
            nautilus
            gnome-system-monitor
            gedit
            gparted
            git
            wget
            curl
            htop
            neofetch
            networkmanager
          ];

          # Customize networking
          networking = {
            networkmanager.enable = true;
            wireless.enable = false; # NetworkManager handles this
            firewall.enable = true;
          };

          # Enable sound
          # sound.enable = true;
          hardware.pulseaudio.enable = false;

          # Enable touchpad support
          services.xserver.libinput.enable = true;

          # Set up localization
          i18n.defaultLocale = "en_US.UTF-8";
          time.timeZone = "UTC";

          # Enable SSH for remote access if needed
          services.openssh.enable = true;
          services.openssh.permitRootLogin = "no";

          # Auto login to GNOME
          services.xserver.displayManager.autoLogin = {
            enable = true;
            user = "nixos";
          };

          # Disable root login
          users.users.root.hashedPassword = "!";

          # Automatically detect and mount filesystems
          services.gvfs.enable = true;
          services.udisks2.enable = true;

          # Enable firmware with common wireless drivers
          #hardware.enableAllFirmware = true;

          # Enable bluetooth
          hardware.bluetooth.enable = true;
          services.blueman.enable = true;
        })
      ];
    };
  };
}
