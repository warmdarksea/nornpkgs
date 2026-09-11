{
  description = "flake for managing systems of *.gensokyo.internal";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # nixpkgs.url = "git+file:///home/clownpiece/src/nixpkgs?ref=gensokyo-master&rev=90a81b8f3db208bfc05c90f2061969706d71fe89";
    # nixpkgs.url = "git+file:///home/clownpiece/src/nixpkgs?rev=bfc1b8a4574108ceef22f02bafcf6611380c100d";
    # nixpkgs.url = "github:nixos/nixpkgs/26f079d4265d403f27f164336c7e20d774d91393";

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
    gensokyo-private = {
      url = "git+file:///home/clownpiece/src/gensokyo-private";
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

    gensokyo-private,
      ... }@inputs: let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
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
    };
    homeManagerModules.magician = { config, lib, pkgs, ... }: {
      imports = [ ./home/common.nix ./home/magician.nix ];
      _module.args = {
        nixpak = nixpak;
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

    nixosConfigurations.eientei = lib.nixosSystem {
      system = "i686-linux";
      modules = [
        {
          networking.hostName = "eientei";
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
        }
        self.nixosModules.base
        lanzaboote.nixosModules.lanzaboote
        (gensokyo-private.nixosModules.furnace or {})
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

    nixosConfigurations.library = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "library";
          networking.hostId = "AAAAAAAA";
        }
        self.nixosModules.base
        self.nixosModules.defaultOverlays
        lanzaboote.nixosModules.lanzaboote
        ./sys/library/configuration.nix
        #./sys/library/hardware-configuration.nix
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
        self.nixosModules.base
        ./sys/minimal.nix
        {
          hostName = "gensokyo-installer";
          # ISO image configuration
          isoImage.makeEfiBootable = true;
          isoImage.makeUsbBootable = true;
          isoImage.compressImage = true;
        }
      ];
    };

    nixosConfigurations.iso-livecd = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-gnome.nix"
        self.nixosModules.base
        ./sys/livecd.nix
      ];
    };

    nixosConfigurations.gensokyo-recovery = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "gensokyo-recovery";
          networking.hostId = "AAAAAAAA";
        }
        self.nixosModules.base
        ./sys/minimal.nix
        ./sys/recovery.nix   # the new module
      ];
    };

    packages.x86_64-linux.claude-env = pkgs.buildEnv {
      name = "claude-env";
      paths = with pkgs; [ nix gitMinimal bash coreutils ];
    };

    # and, mirroring your existing packages.<arch>.images.<name> pattern:
    images.gensokyo-recovery =
      self.nixosConfigurations.gensokyo-recovery.config.system.build.image;
    };
}
