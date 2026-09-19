{
  description = "nornpkgs — systems of *.gensokyo.internal";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # nixpkgs.url = "git+file:///home/clownpiece/src/nixpkgs?ref=gensokyo-master&rev=90a81b8f3db208bfc05c90f2061969706d71fe89";
    # nixpkgs.url = "git+file:///home/clownpiece/src/nixpkgs?rev=bfc1b8a4574108ceef22f02bafcf6611380c100d";
    # nixpkgs.url = "github:nixos/nixpkgs/26f079d4265d403f27f164336c7e20d774d91393";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

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

    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # some configuration options don't make sense to host publicly, even though
    # they're not strictly "secret" in the sense that they don't directly
    # contain credentials (e.g., knowledge of VPN endpoints could be used to
    # correlate identities, etc). so, some options are stored in a local private
    # git repo
    # the public branch is a stub whose per-host modules are all empty; when
    # building locally, override this input to the private branch:
    #   make ... PRIVATE_FLAKE='git+file:///home/clownpiece/src/gensokyo-private?ref=private'
    gensokyo-private = {
      url = "github:warmdarksea/gensokyo-private/public";
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

    nix-minecraft,

    gensokyo-private,
      ... }@inputs: let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        lib = nixpkgs.lib;

        # littledevil modules (akkoma on oracle cloud):
        # bootstrap is for boot volumes and ssh
        # live is for running the actual services (e.g. akkoma)
        # prod is for hooking up to external services (e.g. grafana)
        ldModules = {
          bootstrap = import ./sys/littledevil/bootstrap.nix;
          live = import ./sys/littledevil/live.nix;
          live_test = import ./sys/littledevil/live_test.nix;
          prod = import ./sys/littledevil/prod.nix;
          oci = import ./sys/littledevil/oci.nix;
          libvirt = import ./sys/littledevil/libvirt.nix;
          minecraft = { config, pkgs, lib, ... }: {
            imports = [ nix-minecraft.nixosModules.minecraft-servers ];
            services.minecraft-servers = {
              enable = true;
              eula = true;
              openFirewall = true;
              dataDir = "/data/minecraft";
              servers.vanilla = {
                enable = true;
                jvmOpts = "-Xmx4G -Xms2G";

                # Specify the custom minecraft server package
                package = nix-minecraft.packages.x86_64-linux.vanilla-server;
              };
            };
          };
        };
    in {
    # nix modules

    nixosModules.base = import lib/base.nix;
    nixosModules.desktop = import lib/desktop.nix;
    nixosModules.server = import lib/server.nix;
    nixosModules.nvidia = import lib/nvidia.nix;
    nixosModules.agent = import lib/agent.nix;
    nixosModules.defaultOverlays = { config, pkgs, lib, ... }: {
      nixpkgs.overlays = [
        (self: super: {
          # NanoKVM boot-control tooling (sources pinned in the let above).
          # Built against the overlaid pkgs so cross/other systems stay correct.
          nanokvm = self.python3Packages.callPackage "${nanokvmctlSrc}/nanokvm.nix" { };
          nanokvmctl = self.python3Packages.callPackage "${nanokvmctlSrc}/default.nix" {
            nanokvm = self.nanokvm;
          };
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
        (gensokyo-private.nixosModules.abandonedfactory or {})
        lanzaboote.nixosModules.lanzaboote
        #"${nixpkgs}/nixos/modules/installer/sd-card/sd-image-x86_64.nix"
        ./hw/lattepanda_v1.nix
        ./sys/abandonedfactory/hardware-configuration.nix
        ./sys/abandonedfactory.nix
      ];
    };
 

    nixosConfigurations.cheese = lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            networking.hostName = "cheese";
            networking.hostId = lib.mkDefault "00000000";
          }
          self.nixosModules.base
          (gensokyo-private.nixosModules.cheese or {})
          self.nixosModules.desktop
          self.nixosModules.defaultOverlays
          nixos-hardware.nixosModules.gpd-pocket-3
          ./hw/gpd_pocket_3.nix
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
          networking.hostId = lib.mkDefault "00000000";
        }
        self.nixosModules.base
        (gensokyo-private.nixosModules.chireiden or {})
        self.nixosModules.desktop
        self.nixosModules.defaultOverlays
        lanzaboote.nixosModules.lanzaboote
        nixos-hardware.nixosModules.lenovo-thinkpad-x13-amd
        ./hw/lenovo_thinkpad_x13_gen2.nix
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
          networking.hostId = lib.mkDefault "00000000";
        }
        self.nixosModules.base
        (gensokyo-private.nixosModules.dusk or {})
        self.nixosModules.desktop
        self.nixosModules.defaultOverlays
        lanzaboote.nixosModules.lanzaboote
        ./hw/gpd_pocket_2.nix
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
          networking.hostId = lib.mkDefault "00000000";
        }
        self.nixosModules.base
        (gensokyo-private.nixosModules.eientei or {})
        self.nixosModules.defaultOverlays
        ./hw/eeepc.nix
        ./sys/eientei.nix
      ];
    };

    nixosConfigurations.furnace = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "furnace";
          networking.hostId = lib.mkDefault "00000000";
        }
        self.nixosModules.base
        lanzaboote.nixosModules.lanzaboote
        (gensokyo-private.nixosModules.furnace or {})
        ./hw/ugreen_dxp2800.nix
        ./sys/furnace/configuration.nix
        ./sys/furnace/hardware-configuration.nix
      ];
    };

    nixosConfigurations.hell = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "hell";
          gensokyo-agent = {
            enable = true;
            user = "clownpiece";
          };
          nixpkgs.config = {
            #cudaSupport = true;
            cudaCapabilities = [ "8.9" ];
          };
        }
        self.nixosModules.base
        self.nixosModules.agent
        self.nixosModules.desktop
        self.nixosModules.nvidia
        self.nixosModules.defaultOverlays
        gensokyo-private.nixosModules.hell
        lanzaboote.nixosModules.lanzaboote
        nixos-hardware.nixosModules.common-cpu-amd
        nixos-hardware.nixosModules.common-cpu-amd-pstate
        nixos-hardware.nixosModules.common-gpu-amd
        nixos-hardware.nixosModules.common-pc-laptop
        nixos-hardware.nixosModules.common-pc-laptop-ssd
        ./hw/asus_x13_flow.nix
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
          gensokyo-agent = {
            enable = true;
            user = "patchouli";
          };
          nixpkgs.config = {
            cudaSupport = true;
            cudaCapabilities = [ "8.6" ];
          };
        }
        self.nixosModules.base
        self.nixosModules.agent
        self.nixosModules.server
        self.nixosModules.defaultOverlays
        (gensokyo-private.nixosModules.library or {})
        lanzaboote.nixosModules.lanzaboote
        ./hw/library.nix
        ./sys/library/configuration.nix
      ];
    };

    nixosConfigurations.magic = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "magic";
          networking.hostId = lib.mkDefault "00000000";
        }
        self.nixosModules.base
        (gensokyo-private.nixosModules.magic or {})
        self.nixosModules.defaultOverlays
        lanzaboote.nixosModules.lanzaboote
        ./hw/magic.nix
        ./sys/magic/configuration.nix
      ];
    };

    nixosConfigurations.mausoleum = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "mausoleum";
          networking.hostId = lib.mkDefault "00000000";
        }
        self.nixosModules.base
        (gensokyo-private.nixosModules.mausoleum or {})
        ./hw/mausoleum.nix
        ./sys/mausoleum/configuration.nix
        ./sys/mausoleum/hardware-configuration.nix
      ];
    };

    nixosConfigurations.sea = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          networking.hostName = "sea";
          networking.hostId = lib.mkDefault "00000000";
        }
        self.nixosModules.base
        (gensokyo-private.nixosModules.sea or {})
        self.nixosModules.desktop
        self.nixosModules.defaultOverlays
        lanzaboote.nixosModules.lanzaboote
        nixos-hardware.nixosModules.dell-xps-13-9310
        ./hw/dell_xps_13_9310.nix
        ./sys/sea/configuration.nix
        ./sys/sea/hardware-configuration.nix
        home-manager.nixosModules.home-manager {
          home-manager.useUserPackages = true;
          home-manager.useGlobalPkgs = true;
          home-manager.users."seija" = self.homeManagerModules.magician;
        }
      ];
    };

    # littledevil (oracle cloud VM.Standard.A1.Flex + local test variants)

    # base
    littledevil.aarch64.nixosConfigurations.base-bootstrap = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ldModules.bootstrap
        self.nixosModules.server
        { nixpkgs.crossSystem.system = "aarch64-linux"; }
      ];
    };

    littledevil.x86_64.nixosConfigurations.base-bootstrap = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ldModules.bootstrap
        self.nixosModules.server
      ];
    };

    littledevil.aarch64.nixosConfigurations.base-live = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ldModules.live
        ldModules.bootstrap
        self.nixosModules.server
        { nixpkgs.crossSystem.system = "aarch64-linux"; }
      ];
    };

    littledevil.x86_64.nixosConfigurations.base-live = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ldModules.bootstrap
        self.nixosModules.server
        ldModules.live
      ];
    };

    # oci
    littledevil.aarch64.images.oci-bootstrap = self.littledevil.aarch64.nixosConfigurations.oci-bootstrap.config.system.build.OCIImage;
    littledevil.x86_64.images.oci-bootstrap = self.littledevil.x86_64.nixosConfigurations.oci-bootstrap.config.system.build.OCIImage;

    littledevil.aarch64.nixosConfigurations.oci-bootstrap = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hw/oci_a1flex.nix
        ldModules.oci
        ldModules.bootstrap
        self.nixosModules.server
        { nixpkgs.crossSystem.system = "aarch64-linux"; }
        "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
        {
          oci.efi = lib.mkForce true;
          boot.loader.grub.enable = lib.mkForce false;
          boot.loader.systemd-boot.enable = true;
        }
      ];
    };

    littledevil.x86_64.nixosConfigurations.oci-bootstrap = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ldModules.oci
        ldModules.bootstrap
        self.nixosModules.server
        "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
        {
          oci.efi = lib.mkForce false;
        }
      ];
    };

    littledevil.x86_64.nixosConfigurations.oci-live = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ldModules.oci
        ldModules.live
        ldModules.prod
        ldModules.bootstrap
        self.nixosModules.server
        (gensokyo-private.nixosModules.littledevil-prod or {})
        "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
        {
          oci.efi = lib.mkForce false;
          systemd.services.akkoma.environment = {
            ERL_FLAGS = "+MIscs 256";
          };
        }
      ];
    };

    littledevil.aarch64.nixosConfigurations.oci-live = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hw/oci_a1flex.nix
        ldModules.oci
        ldModules.live
        ldModules.minecraft
        ldModules.prod
        ldModules.bootstrap
        self.nixosModules.server
        (gensokyo-private.nixosModules.littledevil-prod or {})
        {
          nixpkgs.localSystem.system = "x86_64-linux";
          nixpkgs.crossSystem.system = "aarch64-linux";
        }
        "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
        {
          oci.efi = lib.mkForce true;
          boot.loader.grub.enable = lib.mkForce false;
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = lib.mkForce true;
        }
      ];
    };

    # what actually runs on the oracle instance
    nixosConfigurations.littledevil-prod-bootstrap = self.littledevil.aarch64.nixosConfigurations.oci-bootstrap;
    nixosConfigurations.littledevil-prod = self.littledevil.aarch64.nixosConfigurations.oci-live;

    devShells.x86_64-linux.littledevil = pkgs.mkShell {
      packages = with pkgs; [
        #aliyun-cli
        #awscli2
        #azure-cli
        bruno
        libvirt
        m4
        oci-cli
        wireshark
        wrangler
        zap
        (opentofu.withPlugins (p: [
          p.hashicorp_null
          p.hashicorp_tls
          p.dmacvicar_libvirt
          #p.hashicorp_aws
          #p.hashicorp_azurerm
          #p.aliyun_alicloud
          p.oracle_oci
          p.cloudflare_cloudflare
        ]))
      ];

      shellHook = ". secret/credentials.sh";
    };

    # iso derivations
    nixosConfigurations.iso-minimal = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        self.nixosModules.base
        ./sys/minimal.nix
        {
          networking.hostName = "gensokyo-installer";
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
          networking.hostId = lib.mkDefault "00000000";
        }
        self.nixosModules.base
        ./sys/minimal.nix
        ./sys/recovery.nix   # the new module
      ];
    };

    # flake templates: nix flake init -t github:warmdarksea/nornpkgs#rust-hello

    templates.coq-hellovst = {
      path = ./template/coq-hellovst;
      description = "coq + VST/CompCert: a C fibonacci program verified end to end (needs unfree CompCert)";
      welcomeText = "# coq-hellovst\nproofs: nix flake check  binary: nix run  axioms: nix develop --command make audit";
    };

    templates.lean4-hello = {
      path = ./template/lean4-hello;
      description = "lean 4 hello world (nix build + lean devshell)";
      welcomeText = "# lean4-hello\nbuild: make build  run: make run  test: make test";
    };

    templates.lean4-hellomath = {
      path = ./template/lean4-hellomath;
      description = "lean 4 proofs with mathlib; building type-checks them";
      welcomeText = "# lean4-hellomath\nbuild (= check the proofs): make build";
    };

    templates.py-hello = {
      path = ./template/py-hello;
      description = "python hello world (nix build + pytest devshell)";
      welcomeText = "# py-hello\nbuild: make build  run: make run  test: make test";
    };

    templates.py-hellotorch = {
      path = ./template/py-hellotorch;
      description = "python + torch gpu matmul (builds without a gpu; running needs one)";
      welcomeText = "# py-hellotorch\nbuild: make build  run (needs gpu): make run  test: make test";
    };

    templates.rust-hello = {
      path = ./template/rust-hello;
      description = "rust hello world (nix build + rust devshell)";
      welcomeText = "# rust-hello\nbuild: make build  run: make run  test: make test";
    };

    templates.rust-hellocuda = {
      path = ./template/rust-hellocuda;
      description = "rust + cuda saxpy via runtime nvrtc (builds without a gpu; running needs one)";
      welcomeText = "# rust-hellocuda\nbuild: make build  run (needs gpu): make run  test: make test";
    };

    packages.x86_64-linux.claude-env = pkgs.buildEnv {
      name = "claude-env";
      paths = with pkgs; [ nix gitMinimal bash coreutils ];
    };

    # NanoKVM boot-control tooling.
    packages.x86_64-linux.uefi_trampoline = let
      uefiTrampolineSrc = builtins.fetchGit {
        url = "https://github.com/warmdarksea/uefi_trampoline.git";
        rev = "b5f226568a350f7ec9744e2edca2526686839467";
        ref = "master";
      };
    in pkgs.callPackage "${uefiTrampolineSrc}/default.nix" { }; # .override { bootId = N; }
    packages.x86_64-linux.nanokvm = pkgs.python3Packages.callPackage "${nanokvmctlSrc}/nanokvm.nix" { };;
    packages.x86_64-linux.nanokvmctl = let
      nanokvmctlSrc = builtins.fetchGit {
        url = "https://github.com/warmdarksea/nanokvmctl.git";
        rev = "6778fdbad429af3843563b52899bbb13c46618e9";
        ref = "master";
      };
    in pkgs.python3Packages.callPackage "${nanokvmctlSrc}/default.nix" { inherit nanokvm; };

    # and, mirroring your existing packages.<arch>.images.<name> pattern:
    images.gensokyo-recovery =
      self.nixosConfigurations.gensokyo-recovery.config.system.build.image;
    };
}
