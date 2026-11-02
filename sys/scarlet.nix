import <nixpkgs/nixos> {
  system = "x86_64-linux";
  configuration = { config, lib, pkgs, modulesPath, ... }: {
    imports = [
      ../profile/base.nix
      ../hw/lenovo_thinkpad_x230t.nix
      ../profile/laptop.nix
      ../profile/x11.nix
      ../profile/dev.nix
      ../session/icewm.nix
    ];

    swapDevices = [ ];

    boot.loader.grub.enable = true;
    boot.loader.grub.version = 2;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.hostName = "scarlet";
  services.nscd.enable = true;

  nixpkgs.config.allowUnfree = true;

  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.qemuVerbatimConfig = ''
    dynamic_ownership = 0
  '';

  services.xserver.displayManager.autoLogin = {
    user = "remilia";
    enable = true;
  };

  services.xserver.enable = true;
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;
  services.xserver.desktopManager.plasma5.mobile.enable = true;
  services.xserver.desktopManager.plasma5.mobile.installRecommendedSoftware = true;

  programs = {
    adb.enable = true;
  };

  users.extraUsers.remilia = {
     description = "Remilia Scarlet";
    isNormalUser = true;
    uid = 1000;
    extraGroups = ["wheel" "audio" "video" "pulse" "lxd" "libvirtd" "docker" "adbusers" "networkmanager"];
  };

  environment.systemPackages = with pkgs;
                                                   [awesome rxvt_unicode xfce.tumbler psmisc iptables zfs qemu xf86_input_wacom wireguard-tools plymouth icewm];

  environment.etc."fuse.conf" = { text = ''
    user_allow_other
  '';};

  system.stateVersion = "21.05"; # Did you read the comment?
 };
}
