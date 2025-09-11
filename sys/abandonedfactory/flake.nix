{
  description = "SD Card Image Builder";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations.abandonedfactory = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-x86_64.nix"
        {
          # Basic system configuration
          system.stateVersion = "23.11";
          
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
          networking.hostName = "nixos-sdcard";
          networking.networkmanager.enable = true;

          # SD card specific settings
          sdImage = {
            # Image size (adjust as needed)
            imageBaseName = "nixos-sd-image";
            compressImage = true;

            populateRootCommands = "";
            
            # Optional: customize partition sizes
            # rootPartitionUUID = "00000000-0000-0000-0000-000000000000";
          };
        }
      ];
    };
  };
}
