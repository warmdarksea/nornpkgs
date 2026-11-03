{ config, lib, pkgs, ... }: {
  boot.initrd.systemd.enable = true;
  security.tpm2 = {
    enable = true;
  };

  services.openssh.enable = true;

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "nixos";
  };

  security.sudo.wheelNeedsPassword = false;

  networking.useDHCP = lib.mkDefault true;
  environment.systemPackages = with pkgs; [
    vim
    sbctl
    tpm2-tss
    tpm2-tools
  ];
}
