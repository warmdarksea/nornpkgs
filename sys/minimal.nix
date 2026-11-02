{ config, lib, pkgs, self, inputs, ... }: {
  # Basic system configuration
  networking = {
    firewall.enable = true;
    firewall.allowedTCPPorts = [ 22 ];
  };
  
  # Enable SSH service
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkForce "yes";
      PasswordAuthentication = false;
    };
  };
  
  # Include necessary packages
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    tmux
    smartmontools
    tpm2-tools
  ];

  boot.supportedFilesystems = ["zfs"];
  
  boot.loader.grub.memtest86.enable = true;
  boot.loader.systemd-boot.memtest86.enable = true;
}
