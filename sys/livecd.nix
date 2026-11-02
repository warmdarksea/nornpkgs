{ config, lib, pkgs, self, inputs, ... }: {
  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

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

  networking = {
    networkmanager.enable = true;
    # the graphical installer image force-enables wpa_supplicant, hence mkForce
    wireless.enable = lib.mkForce false; # NetworkManager handles this
    firewall.enable = true;
  };

  hardware.pulseaudio.enable = false;

  services.xserver.libinput.enable = true;

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "UTC";

  services.openssh.enable = true;
  services.openssh.permitRootLogin = "no";

  services.xserver.displayManager.autoLogin = {
    enable = true;
    user = "nixos";
  };

  # Disable root login
  users.users.root.hashedPassword = "!";

  services.gvfs.enable = true;
  services.udisks2.enable = true;

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
}
