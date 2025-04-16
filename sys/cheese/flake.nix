{
  description = "NixOS system: hell";

  inputs = {
    #
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
        url = "github:nix-community/lanzaboote/v0.4.2";
        inputs.nixpkgs.follows = "nixpkgs";
      };

      #
      nix-gensokyo = {
        url = "path:/home/clownpiece/src/nix-gensokyo";
        flake = true;
        inputs.nixpkgs.follows = "nixpkgs";
      };    

      # fixup inputs
      # my-nixpkgs = {
        #   url = "path:/home/clownpiece/src/nixpkgs";
        #   flake = true;
        # };
        #my-nixos-hardware = {
          #  url = "path:/home/clownpiece/src/nixos-hardware";
          #  flake = true;
          #};
          #
          # fixpkgs_blender.url = "github:NixOS/nixpkgs/2af19cfb6aa40768c4bbefd801a136270e099191";
  };

  outputs = {
    self,

    nixpkgs,
    nixos-hardware,
    # emacs-overlay,
    home-manager,
    lanzaboote,
    # nixpak,

    nix-gensokyo,

    # my-nixpkgs,
    # my-nixos-hardware,

    # fixpkgs_blender,
    ... }@inputs: {
      nixosConfigurations.cheese = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nix-gensokyo.nixosModules.base
          nixos-hardware.nixosModules.gpd-pocket-3
          ./configuration.nix
          ./hardware-configuration.nix
          home-manager.nixosModules.home-manager {
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            home-manager.users.nazrin = nix-gensokyo.homeManagerModules.magician;
          }
        ];
      };
    };
}
