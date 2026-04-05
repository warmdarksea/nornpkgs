{
  description = "flake for managing systems of *.gensokyo.internal";

  inputs = {
    nixpkgs.url = "git+file:///home/clownpiece/src/nixpkgs";
    nixos-hardware.url = "git+file:///home/clownpiece/src/nixos-hardware?ref=gensokyo-master";

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
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # some configuration options don't make sense to host publicly, even though
    # they're not strictly "secret" in the sense that they don't directly
    # contain credentials (e.g., knowledge of VPN endpoints could be used to
    # correlate identities, etc). so, some options are stored in a local private
    # git repo
    gensokyo-infra-private = {
      url = "git+file:///home/clownpiece/src/gensokyo-infra-private";
    };

    # more config
    gensokyo-dotfiles = {
      url = "path:/home/clownpiece/src/gensokyo-dotfiles";
      flake = false;
    };

    nornpkgs = {
      url = "path:/home/clownpiece/src/nornpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
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
  };

  outputs = {
    self,
      
    nixpkgs,
    nixos-hardware,

    emacs-overlay,
    home-manager,
    lanzaboote,

    nixpak,

    gensokyo-dotfiles,
    nornpkgs,

    iso-minimal,
    iso-livecd,
      ... }@inputs: let
     lib = nixpkgs.lib;
    in {
    # nix modules

    nixosModules.base = import lib/base.nix;
    nixosModules.nvidia = import lib/nvidia.nix;
    nixosModules.defaultOverlays = { config, pkgs, lib, ... }: {
      nixpkgs.overlays = [
        (self: super: {
          # ...
        })
        (final: prev: {
          # https://github.com/NixOS/nixpkgs/issues/493503
          guile-zlib = prev.guile-zlib.overrideAttrs { doCheck = false; };
        })
        emacs-overlay.overlays.default
        emacs-overlay.overlays.package
      ];
    };

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
        nornpkgs = nornpkgs;
      };
    };

    # systems            
    nixosConfigurations.abandonedfactory = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "abandonedfactory";
        }
        self.nixosModules.base
        lanzaboote.nixosModules.lanzaboote
        #"${nixpkgs}/nixos/modules/installer/sd-card/sd-image-x86_64.nix"
        ./sys/abandonedfactory/hardware-configuration.nix
        ./sys/abandonedfactory.nix
      ];
    };
 

    nixosConfigurations.cheese = lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            networking.hostName = "cheese";
            networking.hostId = "AAAAAAAA";
          }
          self.nixosModules.base
          self.nixosModules.defaultOverlays
          nixos-hardware.nixosModules.gpd-pocket-3
          ./sys/cheese/configuration.nix
          ./sys/cheese/hardware-configuration.nix
          home-manager.nixosModules.home-manager {
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            home-manager.users.nazrin = self.homeManagerModules.magician;
          }
        ];
      };

    nixosConfigurations.chireiden = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "chireiden";
          networking.hostId = "AAAAAAAA";
        }
        self.nixosModules.base
        self.nixosModules.defaultOverlays
        lanzaboote.nixosModules.lanzaboote
        nixos-hardware.nixosModules.lenovo-thinkpad-x13-amd
        ./sys/chireiden/configuration.nix
        ./sys/chireiden/hardware-configuration.nix
        home-manager.nixosModules.home-manager {
          home-manager.useUserPackages = true;
          home-manager.useGlobalPkgs = true;
          home-manager.users."satori" = self.homeManagerModules.magician;
        }
      ];
    };

    nixosConfigurations.dusk = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "dusk";
          networking.hostId = "AAAAAAAA";
        }
        self.nixosModules.base
        self.nixosModules.defaultOverlays
        lanzaboote.nixosModules.lanzaboote
        ./sys/dusk/configuration.nix
        ./sys/dusk/hardware-configuration.nix
        home-manager.nixosModules.home-manager {
          home-manager.useUserPackages = true;
          home-manager.useGlobalPkgs = true;
          home-manager.users."rumia" = self.homeManagerModules.magician;
        }
      ];
    };

    nixosConfigurations.furnace = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "furnace";
          networking.hostId = "AAAAAAAA";
        }
        self.nixosModules.base
        lanzaboote.nixosModules.lanzaboote
        ./sys/furnace/configuration.nix
        ./sys/furnace/hardware-configuration.nix
      ];
    };

    nixosConfigurations.hell = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "hell";
          networking.hostId = "AAAAAAAA";
        }
        self.nixosModules.base
        self.nixosModules.nvidia
        self.nixosModules.defaultOverlays
        lanzaboote.nixosModules.lanzaboote
        nixos-hardware.nixosModules.asus-x13-flow
        ./sys/hell/configuration.nix
        ./sys/hell/hardware-configuration.nix
        home-manager.nixosModules.home-manager {
          home-manager.useUserPackages = true;
          home-manager.useGlobalPkgs = true;

          home-manager.users.clownpiece = self.homeManagerModules.magician;
          home-manager.users.seiran = self.homeManagerModules.common;
        }
      ];
    };

    nixosConfigurations.magic = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "magic";
          networking.hostId = "AAAAAAAA";
        }
        self.nixosModules.base
        self.nixosModules.defaultOverlays
        lanzaboote.nixosModules.lanzaboote
        ./sys/magic/configuration.nix
        ./sys/magic/hardware-configuration.nix
      ];
    };

    nixosConfigurations.mausoleum = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "mausoleum";
          networking.hostId = "AAAAAAAA";
        }
        self.nixosModules.base
        ./mausoleum/configuration.nix
        ./mausoleum/hardware-configuration.nix
      ];
    };

    nixosConfigurations.sea = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "sea";
          networking.hostId = "AAAAAAAA";
        }
        self.nixosModules.base
        self.nixosModules.defaultOverlays
        lanzaboote.nixosModules.lanzaboote
        nixos-hardware.nixosModules.dell-xps-13-9310
        ./sys/sea/configuration.nix
        ./sys/sea/hardware-configuration.nix
        home-manager.nixosModules.home-manager {
          home-manager.useUserPackages = true;
          home-manager.useGlobalPkgs = true;
          home-manager.users."seija" = self.homeManagerModules.magician;
        }
      ];
    };

    # iso derivations
    nixosConfigurations.iso-minimal = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        ./sys/minimal.nix
      ];
    };

    nixosConfigurations.iso-livecd = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-gnome.nix"
        ./sys/livecd.nix
      ];
    };
  };
}
