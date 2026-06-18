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
  
  # Add your SSH public key for access
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted"
  ];
  
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
  #boot.kernelParams = [ "console=ttyUSB0,115200" "console=tty0" ];
  
  # Enable getty on ttyUSB0
  #systemd.services."serial-getty@ttyUSB0".enable = true;
  
  boot.loader.grub.memtest86.enable = true;
  boot.loader.systemd-boot.memtest86.enable = true;
}
