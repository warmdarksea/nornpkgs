{
  description = "Minimal ISO image with SSH key";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: 
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations.iso-minimal = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        (
          { pkgs, lib, ... }: {
            # ISO image configuration
            isoImage.makeEfiBootable = true;
            isoImage.makeUsbBootable = true;
            isoImage.compressImage = true;
            
            # Basic system configuration
            networking = {
              hostName = "minimal-iso";
              firewall.enable = true;
              firewall.allowedTCPPorts = [ 22 ];
            };
            
            # Enable SSH service
            services.openssh = {
              enable = true;
              settings = {
                PermitRootLogin = "yes";
                PasswordAuthentication = false;
              };
            };
            
            # Add your SSH public key for access
            users.users.root.openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted..." # Replace with your SSH public key
            ];
            
            # Include necessary packages
            environment.systemPackages = with pkgs; [
              vim
              git
              wget
              curl
            ];
          }
        )
      ];
    };
  };
}
