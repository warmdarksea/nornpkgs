{ config, lib, pkgs, self, inputs, ... }: {
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
    fastfetch
    networkmanager
  ];

  # Customize networking
  networking = {
    networkmanager.enable = true;
    # the graphical installer image force-enables wpa_supplicant, hence mkForce
    wireless.enable = lib.mkForce false; # NetworkManager handles this
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
}
