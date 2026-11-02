{ config, lib, pkgs, self, inputs, ... }: {
  system.stateVersion = "23.11";

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.initrd.systemd.enable = true;
  boot.kernelParams = ["intel_idle.max_cstate=1" "acpi_osi=\"Windows 2015\"" "nomodeset"];
  security.tpm2 = {
    enable = true;
  };

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
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
