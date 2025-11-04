{
  description = "A simple NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      #url = "github:nix-community/lanzaboote/pull/487/head";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        rust-overlay.follows = "rust-overlay";
      };
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # more config
    gensokyo-dotfiles = {
      url = "path:/home/clownpiece/src/gensokyo-dotfiles";
      flake = false;
    };

    # systems
    abandonedfactory = {
      url = "path:./sys/abandonedfactory";

      inputs.nixpkgs.follows = "nixpkgs";
      #inputs.nixos-hardware.follows = "my-nixos-hardware";
      inputs.nix-gensokyo.follows = ""; # self-reference
    };

    cheese = {
      url = "path:./sys/cheese";

      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixos-hardware.follows = "my-nixos-hardware";
      inputs.nix-gensokyo.follows = ""; # self-reference
    };

    furnace = {
      url = "path:./sys/furnace";

      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixos-hardware.follows = "my-nixos-hardware";
      inputs.nix-gensokyo.follows = ""; # self-reference
    };

    hell = {
      url = "path:./sys/hell";

      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixos-hardware.follows = "my-nixos-hardware";
      inputs.home-manager.follows = "home-manager";
      inputs.lanzaboote.follows = "lanzaboote";
      inputs.nix-gensokyo.follows = ""; # self-reference
    };

    magic = {
      url = "path:./sys/magic";

      inputs.nixpkgs.follows = "nixpkgs";
      #inputs.nixos-hardware.follows = "my-nixos-hardware";
      inputs.home-manager.follows = "home-manager";
      inputs.nix-gensokyo.follows = ""; # self-reference
    };

    # installer/livecd derivations
    iso-minimal = {
      url = "path:./iso/minimal";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    iso-livecd = {
      url = "path:./iso/livecd";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # fixup/overlay inputs
    my-nixpkgs = {
      url = "path:/home/clownpiece/src/nixpkgs";
      flake = true;
    };
    my-nixos-hardware = {
      url = "path:/home/clownpiece/src/nixos-hardware";
      flake = true;
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    # example of specific nixpkgs commit
    # fixpkgs_foo.url = "github:NixOS/nixpkgs/2af19cfb6aa40768c4bbefd801a136270e099191";
  };

  outputs = { self,

  nixpkgs,
  nixos-hardware,
  emacs-overlay,
  home-manager,
  lanzaboote,
  nixpak,

  gensokyo-dotfiles,
              
  abandonedfactory,
  cheese,
  furnace,
  hell,
  magic,

  iso-minimal,
  iso-livecd,

  my-nixpkgs,
  my-nixos-hardware,

  # fixpkgs_foo,

  ... }@inputs: let
    overlay = { config, pkgs, lib, ... }: {
      nixpkgs.overlays = [
        # Overlay 1: Use `self` and `super` to express
        # the inheritance relationship
        (self: super: {
          # ...
        })
        emacs-overlay.overlays.default
        emacs-overlay.overlays.package
      ];
    };
  in {
    # nix modules

    nixosModules.base = import lib/base.nix;
    #nixosModules.gensokyo = import lib/gensokyo.nix;
    nixosModules.nvidia = import lib/nvidia.nix;

    # home manager modules

    homeManagerModules.common = { config, lib, pkgs, ... }: {
      imports = [ ./home/common.nix ];
      _module.args.dotfiles = gensokyo-dotfiles;
    };
    homeManagerModules.magician = { config, lib, pkgs, ... }: {
      imports = [ ./home/common.nix ./home/magician.nix ];
      _module.args = {
        dotfiles = gensokyo-dotfiles;
        nixpak = nixpak;
      };
    };

    # systems            
    # nixosConfigurations.cheese = nixpkgs.lib.nixosSystem {
    #   system = "x86_64-linux";
    #   modules = [
    #     nixos-hardware.nixosModules.gpd-pocket-3
    #     ./sys/cheese/configuration.nix
    #     ./sys/cheese/hardware-configuration.nix
    #     home-manager.nixosModules.home-manager {
    #       home-manager.useUserPackages = true;
    #       home-manager.useGlobalPkgs = true;
    #       #          home-manager.users."satori" = {};
    #     }
    #   ];
    # };

    nixosConfigurations.abandonedfactory = abandonedfactory.nixosConfigurations.abandonedfactory.extendModules { modules = [ ]; };

    nixosConfigurations.cheese = cheese.nixosConfigurations.cheese.extendModules { modules = [ overlay ]; };

    nixosConfigurations.chireiden = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        lanzaboote.nixosModules.lanzaboote
        nixos-hardware.nixosModules.lenovo-thinkpad-x13-amd
        ./sys/chireiden/configuration.nix
        ./sys/chireiden/hardware-configuration.nix
        ./lib/base.nix
        home-manager.nixosModules.home-manager {
          home-manager.useUserPackages = true;
          home-manager.useGlobalPkgs = true;
          home-manager.users."satori" = import ./home.nix;
        }
      ];
    };

    nixosConfigurations.dusk = my-nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        lanzaboote.nixosModules.lanzaboote
        #        nixos-hardware.nixosModules.gpd-pocket-3
        ./sys/dusk/configuration.nix
        ./sys/dusk/hardware-configuration.nix
        ./lib/base.nix
        home-manager.nixosModules.home-manager {
          home-manager.useUserPackages = true;
          home-manager.useGlobalPkgs = true;
          #          home-manager.users."satori" = {};
          home-manager.users."rumia" = import ./home.nix;
        }
      ];
    };

    nixosConfigurations.furnace = furnace.nixosConfigurations.furnace.extendModules { modules = [ ]; };
    nixosConfigurations.hell = hell.nixosConfigurations.hell.extendModules { modules = [ overlay ]; };
    nixosConfigurations.magic = magic.nixosConfigurations.magic.extendModules { modules = [ ]; };

    # nixosConfigurations.magic = nixpkgs.lib.nixosSystem {
    #   system = "x86_64-linux";
    #   modules = [
    #     ./sys/magic/configuration.nix
    #     ./sys/magic/hardware-configuration.nix
    #     ./lib/base.nix
    #   ];
    # };

    nixosConfigurations.mausoleum = my-nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # lanzaboote.nixosModules.lanzaboote
        #  nixos-hardware.nixosModules.gpd-pocket-3
        ./mausoleum/configuration.nix
        ./mausoleum/hardware-configuration.nix
        ./base.nix
        # home-manager.nixosModules.home-manager {
          # home-manager.useUserPackages = true;
          # home-manager.useGlobalPkgs = true;
          # home-manager.users."satori" = {};
          # home-manager.users."yoshika" = import ./home.nix;
          # }
      ];
    };

    nixosConfigurations.sea = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        lanzaboote.nixosModules.lanzaboote
        nixos-hardware.nixosModules.dell-xps-13-9310
        ./sys/sea/configuration.nix
        ./sys/sea/hardware-configuration.nix
        ./lib/base.nix
        home-manager.nixosModules.home-manager {
          home-manager.useUserPackages = true;
          home-manager.useGlobalPkgs = true;
          home-manager.users."seija" = import ../home/seija.nix;
        }
      ];
    };

    # iso derivations
    nixosConfigurations.iso-minimal = iso-minimal.nixosConfigurations.iso-minimal.extendModules {};
    nixosConfigurations.iso-livecd = iso-livecd.nixosConfigurations.iso-livecd.extendModules {};
  };
}
