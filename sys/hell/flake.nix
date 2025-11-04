{
  description = "NixOS system: hell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    #emacs-overlay = {
    #  url = "github:nix-community/emacs-overlay";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-gensokyo = {
      url = "path:/home/clownpiece/src/nix-gensokyo";
      flake = true;
    };
  };

  outputs = {
    self,

      nixpkgs,
      nixos-hardware,
      # emacs-overlay,
      home-manager,
      lanzaboote,

      nix-gensokyo,
      ... }@inputs: {
        nixosConfigurations.hell = let
          system = "x86_64-linux";
          pkgs = nixpkgs.legacyPackages.${system};
        in nixpkgs.lib.nixosSystem {
          system = "${system}";
          modules = [
            lanzaboote.nixosModules.lanzaboote
            nixos-hardware.nixosModules.asus-x13-flow
            ./configuration.nix
            ./hardware-configuration.nix
            nix-gensokyo.nixosModules.base
            nix-gensokyo.nixosModules.nvidia
            home-manager.nixosModules.home-manager {
              # home-manager.extraSpecialArgs = {
              # 
              # };

              home-manager.useUserPackages = true;
              home-manager.useGlobalPkgs = true;

              home-manager.users.clownpiece = nix-gensokyo.homeManagerModules.magician;
              home-manager.users.seiran = nix-gensokyo.homeManagerModules.common;
            }
          ];
        };
      };
}
