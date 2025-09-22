{
  description = "SD Card Image Builder";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #
    nix-gensokyo = {
      url = "path:/home/clownpiece/src/nix-gensokyo";
      flake = true;
      inputs.nixpkgs.follows = "nixpkgs";
    };  
  };

  outputs = {
    self,
      nixpkgs ,
      # emacs-overlay,
      #home-manager,
      lanzaboote,
      # nixpak,

      nix-gensokyo
  }: {
    nixosConfigurations.abandonedfactory = let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;
    in nixpkgs.lib.nixosSystem {
      system = "${system}";
      modules = [
        nix-gensokyo.nixosModules.base
        lanzaboote.nixosModules.lanzaboote
        #"${nixpkgs}/nixos/modules/installer/sd-card/sd-image-x86_64.nix"
        ./hardware-configuration.nix
        {
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
          networking.hostName = "abandonedfactory";
          #networking.networkmanager.enable = true;
          networking.useDHCP = nixpkgs.lib.mkDefault true;
          environment.systemPackages = with pkgs; [
            vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
            #   wget
            sbctl
             tpm2-tss
  tpm2-tools
          ];
        }
      ];
    };
  };
}
