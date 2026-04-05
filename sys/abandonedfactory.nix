{ config, lib, pkgs, self, inputs, ... }: {
  # Basic system configuration
  system.stateVersion = "23.11";

  # Use the systemd-boot EFI boot loader.
  #boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.initrd.systemd.enable = true;
  boot.kernelParams = ["intel_idle.max_cstate=1" "acpi_osi=\"Windows 2015\"" "nomodeset"];
  security.tpm2 = {
    enable = true;
    #pkcs11.enable = true;
    #tctiEnvironment.enable = true;
  };

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
  
  # Enable SSH for remote access
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    # Add your SSH public key here
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted"
  ];

  # Optional: Add a regular user
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "nixos";
  };

  # Enable sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Basic networking
  #networking.networkmanager.enable = true;
  networking.useDHCP = lib.mkDefault true;
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    #   wget
    sbctl
    tpm2-tss
    tpm2-tools
  ];
}
