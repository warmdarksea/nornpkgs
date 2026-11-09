{
  description = "nornpkgs - nix infrastructure for gensokyo.internal";

  # Binary caches. cache.nixos-cuda.org is the nixpkgs CUDA team's cache (the
  # successor of cuda-maintainers.cachix.org, which no longer exists): CUDA
  # builds of nixos-unstable with the *default* cudaCapabilities, which is why
  # no host below narrows cudaCapabilities any more. Declared here so a plain
  # `nix build` of this flake (CI, non-NixOS) picks it up, given
  # --accept-flake-config; the hosts get the same substituter via lib/base.nix.
  nixConfig = {
    # priority 50 keeps it behind cache.nixos.org (40), see lib/base.nix
    extra-substituters = [ "https://cache.nixos-cuda.org?priority=50" ];
    extra-trusted-public-keys = [ "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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

    nix-minecraft,

    gensokyo-private,
      ... }: let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        lib = nixpkgs.lib;
        # pkgs with overlays.default applied; the packages.* outputs for our
        # own packages come from here so they match what the hosts install.
        nornpkgs = pkgs.extend self.overlays.default;
        # gensokyo-private's ci branch exports gensokyo.ci = true; nothing else does.
        ci = gensokyo-private.gensokyo.ci or false;
        # opentofu with tf/'s providers, for the packages.<system>.tofu outputs
        tofuWith = pkgs: pkgs.opentofu.withPlugins (p: [
          p.hashicorp_null
          p.hashicorp_tls
          p.dmacvicar_libvirt
          p.oracle_oci
          p.cloudflare_cloudflare
        ]);

        # Model fetchers (lib/models.nix). A function of the *caller's* pkgs --
        # shadowing the one above is deliberate: the lib output below has to
        # work for whatever nixpkgs the consumer brings.
        modelLib = pkgs: import lib/models.nix pkgs;

        # littledevil modules (akkoma on oracle cloud):
        # bootstrap is for boot volumes and ssh
        # live is for running the actual services (e.g. akkoma)
        # prod is for hooking up to external services (e.g. grafana)
        ldModules = {
          bootstrap = import ./sys/littledevil/bootstrap.nix;
          live = import ./sys/littledevil/live.nix;
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

        # An older nixpkgs (glibc 2.40 toolchain) for audio plugins that must
      # load into hosts running older libcs: a .so can never demand a newer
      # glibc than the host process already has loaded, and the Bitwig
      # flatpak's freedesktop runtime lags nixpkgs-unstable. Plugins built
      # from this pin top out at GLIBC_2.38, which both the flatpak runtimes
      # and every native host here satisfy.
      pkgsCompat = import (builtins.fetchTarball {
        url = "https://github.com/NixOS/nixpkgs/archive/3497aa5c9457a9d88d71fa93a4a8368816fbeeba.tar.gz";
        sha256 = "sha256-dhhvQY67aboBk8b0/u0XB6vwHdgbROZT3fJAjyNh5Ww=";
      }) { system = "x86_64-linux"; config = { }; overlays = [ ]; };

      nanokvmctlSrc = builtins.fetchGit {
        url = "https://github.com/warmdarksea/nanokvmctl.git";
        rev = "e941498c4d0bd51661b5c689a6e1de24eb85fec9";
        ref = "master";
      };
      # gpu-timeshare: many models taking turns on one GPU behind the
      # OpenAI API (batches, a queue, a cache). Its default.nix is not a
      # flake; built against whatever pkgs the overlay lands on.
      gpuTimeshareSrc = builtins.fetchGit {
        url = "https://github.com/warmdarksea/gpu-timeshare.git";
        rev = "250d431293557df591393ffe382d674fe981e653";
        ref = "master";
      };
      # slopbooru: the booru, its classify command, and the fleet of models it
      # asks (fleet/, for gpu-timeshare). Built against this flake's nixpkgs
      # (not slopbooru's own pin, a second nixpkgs to fetch and to drift
      # apart from this one), imported plain:
      # no overlays, no host config, so a host's cudaSupport doesn't rebuild
      # the engine. The engine's cuda wheels are fixed up at build time, so a
      # nixpkgs bump wants a run on the card (slopbooru's fleet/engine.nix).
      slopbooruSrc = builtins.fetchGit {
        url = "https://github.com/warmdarksea/slopbooru.git";
        rev = "cc6b331a1716dc6ce1d9bb27a07761d6e370c1bb";
        ref = "master";
      };
      slopbooruFor = pkgs: import slopbooruSrc {
        inherit (pkgs.stdenv.hostPlatform) system;
        pkgs = import nixpkgs { inherit (pkgs.stdenv.hostPlatform) system; config = { }; overlays = [ ]; };
        inherit ((modelLib pkgs)) fetchHuggingFace;
      };
      uefiTrampolineSrc = builtins.fetchGit {
        url = "https://github.com/warmdarksea/uefi_trampoline.git";
        rev = "b1d84a5752aecdbb62488753060afa9977f7ee11";
        ref = "master";
      };
    in {
    # library functions (not nixos modules). system-agnostic: the caller brings
    # their own pkgs, so this needs no per-system plumbing.
    #
    #   nornpkgs.lib.fetchHuggingFace {
    #     inherit pkgs;
    #     src   = "hf:Qwen/Qwen2.5-7B@d149729398750b98c0af14eb82c78cfe92750796";
    #     files = [ "*.safetensors" "*.json" "merges.txt" ];
    #     hash  = "sha256-...";
    #   }
    #
    # .gguf / .gguf.quant.<type> / .safetensors hang off the result; the whole
    # tree is documented at the top of lib/models.nix.
    lib.fetchModel = { pkgs, ... }@args:
      (modelLib pkgs).fetchModel (removeAttrs args [ "pkgs" ]);
    lib.fetchHuggingFace = { pkgs, ... }@args:
      (modelLib pkgs).fetchHuggingFace (removeAttrs args [ "pkgs" ]);

    # Sandboxed jupyter servers for the templates (lib/jupyter.nix). Same
    # deal as the fetchers: a function of the *caller's* pkgs, so the kernels
    # are built against whatever nixpkgs (and whatever cudaCapabilities) the
    # consuming flake brought.
    #
    #   nornpkgs.lib.mkJupyter {
    #     inherit pkgs;
    #     name = "py-hellotorch";
    #     kernels.python = { packages = ps: [ ps.torch-bin ]; cuda = true; };
    #   }
    #
    # -> bin/jupyter-sandbox start|stop|status|logs|shell|print-cmd, running
    # the server under rootless podman. The extension list and the kernel
    # presets live at the top of lib/jupyter.nix.
    lib.mkJupyter = { pkgs, ... }@args:
      (import lib/jupyter.nix pkgs).mkJupyter (removeAttrs args [ "pkgs" ]);

    # nix modules

    # lib/base.nix plus the CI flag: gensokyo-private's `ci` branch exports
    # gensokyo.ci = true, its other branches nothing (option in lib/ci.nix).
    nixosModules.base = { ... }: {
      imports = [ ./lib/base.nix ];
      gensokyo.ci = ci;
    };
    nixosModules.desktop = import lib/desktop.nix;
    nixosModules.server = import lib/server.nix;
    nixosModules.nvidia = import lib/nvidia.nix;
    nixosModules.agent = import lib/agent.nix;
    # services.gpu-timeshare (the module ships with gpu-timeshare); its package
    # is the overlay's gpu-timeshare. Each model runs in its own sandboxed
    # unit, started and stopped by the service through polkit.
    nixosModules.gpu-timeshare = import "${gpuTimeshareSrc}/nix/module.nix";
    # slopbooru's fleet on it, per host:
    #   services.gpu-timeshare = { enable = true; inherit (pkgs.slopbooru-fleet) models settings; };
    # and on any machine: slopbooru classify --images DIR (classify.toml's
    # backend is http://127.0.0.1:8100/v1; SLOPBOORU_TOKEN from
    # `sudo -u gpu-timeshare gpu-timeshare-admin token add NAME`)

    # The project-wide overlay: our own packages plus emacs-overlay. Every
    # nixosSystem below applies it ({ nixpkgs.overlays = [ self.overlays.default ]; }),
    # and packages.x86_64-linux.* are taken from pkgs with it applied.
    overlays.default = lib.composeManyExtensions [
      (final: prev: {
        # NanoKVM boot-control tooling (sources pinned in the let above),
        # built against the overlaid pkgs so cross/other systems stay correct.
        nanokvm = final.python3Packages.callPackage "${nanokvmctlSrc}/nanokvm.nix" { };
        nanokvmctl = final.python3Packages.callPackage "${nanokvmctlSrc}/default.nix" { inherit (final) nanokvm; };
        # Audio plugins from our forks (pkgs/*, nixpkgs-style). The -compat
        # variants for the Bitwig flatpak stay under packages.*: they need the
        # older glibc pin, not whatever pkgs this overlay lands on.
        gearmulator = final.callPackage ./pkgs/gearmulator { };
        openutau-bridge = final.callPackage ./pkgs/openutau-bridge { };
        # many models taking turns on one GPU (nixosModules.gpu-timeshare runs it)
        gpu-timeshare = import gpuTimeshareSrc { pkgs = final; };
        # the booru (a static binary, with `slopbooru classify`), and the
        # models it asks as gpu-timeshare models: slopbooru-fleet.models for
        # services.gpu-timeshare.models (~75 GB of weights)
        slopbooru = (slopbooruFor final).slopbooru;
        slopbooru-fleet = (slopbooruFor final).fleet;
      })
      emacs-overlay.overlays.default
      emacs-overlay.overlays.package
    ];

    # home manager modules

    homeManagerModules.common = import ./home/common.nix;
    # Audio plugins (VST3/VST2/CLAP/LV2) from packages into ~/.vst3 & friends,
    # see home/audio-plugins.nix for the mechanics.
    homeManagerModules.audioPlugins = import ./home/audio-plugins.nix;
    homeManagerModules.magician = { lib, osConfig ? { }, ... }: {
      imports = [ self.homeManagerModules.common self.homeManagerModules.audioPlugins ];
      # The -compat builds (older glibc), so the plugins also load into the
      # Bitwig flatpak's freedesktop runtime. Not on the CI runner: they are
      # built from the second nixpkgs pin, so nothing of them is cached.
      audioPlugins.packages = lib.optionals (!(osConfig.gensokyo.ci or false)) [
        self.packages.x86_64-linux.gearmulator-compat
        self.packages.x86_64-linux.lsp-plugins-compat
        self.packages.x86_64-linux.openutau-bridge
      ];
    };

    # generic systems: sys/<host> plus its roles and users, no hardware, disks,
    # bootloader or hostname. what the boot tests (checks.*.boot-<host>) run.
    nixosModules.gensokyo.systems = {
      base = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
        ];
      };

      abandonedfactory = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
          ./sys/abandonedfactory
        ];
      };

      cheese = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
          self.nixosModules.desktop
          ./sys/cheese
          home-manager.nixosModules.home-manager {
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            home-manager.users.nazrin = self.homeManagerModules.magician;
          }
        ];
      };

      chireiden = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
          self.nixosModules.desktop
          ./sys/chireiden
          home-manager.nixosModules.home-manager {
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            home-manager.users."satori" = self.homeManagerModules.magician;
          }
        ];
      };

      dusk = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
          self.nixosModules.desktop
          ./sys/dusk
          home-manager.nixosModules.home-manager {
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            home-manager.users."rumia" = self.homeManagerModules.magician;
          }
        ];
      };

      eientei = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
          ./sys/eientei
        ];
      };

      furnace = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
          ./sys/furnace
        ];
      };

      hell = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
          self.nixosModules.agent
          self.nixosModules.desktop
          ./sys/hell
          home-manager.nixosModules.home-manager {
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;

            home-manager.users.clownpiece = self.homeManagerModules.magician;
            home-manager.users.seiran = self.homeManagerModules.common;
          }
        ];
        gensokyo-agent = {
          enable = true;
          user = "clownpiece";
        };
        # no cudaCapabilities: narrowing them changes the hash of every CUDA
        # derivation and misses cache.nixos-cuda.org, which builds the
        # default set (see nixConfig at the top)
        nixpkgs.config = {
          # the CUDA builds are host-only; the runner builds the structure
          cudaSupport = !ci;
        };
      };

      library = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
          self.nixosModules.agent
          self.nixosModules.server
          self.nixosModules.gpu-timeshare
          ./sys/library
        ];
        gensokyo-agent = {
          enable = true;
          user = "patchouli";
        };
        nixpkgs.config = {
          cudaSupport = !ci; # see hell
          # no cudaCapabilities, see hell
        };
      };

      magic = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
          ./sys/magic
        ];
      };

      mausoleum = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
          ./sys/mausoleum
        ];
      };

      sea = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          self.nixosModules.base
          self.nixosModules.desktop
          ./sys/sea
          home-manager.nixosModules.home-manager {
            home-manager.useUserPackages = true;
            home-manager.useGlobalPkgs = true;
            home-manager.users."seija" = self.homeManagerModules.magician;
          }
        ];
      };

      littledevil = {
        imports = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          ldModules.bootstrap
          ldModules.live
          self.nixosModules.server
        ];
        boot.isContainer = false;
      };
    };

    # instances: a generic system plus hw/, the private module and inst/<fqdn>.
    # what `make build_sys_closure TARGET=<host>` builds and deploys.

    # base on a placeholder disk, never deployed; CI builds it on every push
    nixosConfigurations.base = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gensokyo.systems.base
        {
          networking.hostName = "base";
          fileSystems."/" = { device = "/dev/disk/by-label/base-root"; fsType = "ext4"; };
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;
          system.stateVersion = "26.11";
        }
      ];
    };

    nixosConfigurations.abandonedfactory = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gensokyo.systems.abandonedfactory
        (gensokyo-private.nixosModules.abandonedfactory or {})
        lanzaboote.nixosModules.lanzaboote
        ./hw/lattepanda_v1.nix
        ./inst/abandonedfactory.gensokyo.internal
      ];
    };
 

    nixosConfigurations.cheese = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gensokyo.systems.cheese
        (gensokyo-private.nixosModules.cheese or {})
        nixos-hardware.nixosModules.gpd-pocket-3
        ./hw/gpd_pocket_3.nix
        ./inst/cheese.gensokyo.internal
      ];
    };

    nixosConfigurations.chireiden = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gensokyo.systems.chireiden
        (gensokyo-private.nixosModules.chireiden or {})
        lanzaboote.nixosModules.lanzaboote
        nixos-hardware.nixosModules.lenovo-thinkpad-x13-amd
        ./hw/lenovo_thinkpad_x13_gen2.nix
        ./inst/chireiden.gensokyo.internal
      ];
    };

    nixosConfigurations.dusk = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gensokyo.systems.dusk
        (gensokyo-private.nixosModules.dusk or {})
        lanzaboote.nixosModules.lanzaboote
        ./hw/gpd_pocket_2.nix
        ./inst/dusk.gensokyo.internal
      ];
    };

    nixosConfigurations.eientei = lib.nixosSystem {
      # i686: nixpkgs.hostPlatform in sys/eientei
      modules = [
        self.nixosModules.gensokyo.systems.eientei
        (gensokyo-private.nixosModules.eientei or {})
        ./hw/eeepc.nix
        ./inst/eientei.gensokyo.internal
      ];
    };

    nixosConfigurations.furnace = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gensokyo.systems.furnace
        (gensokyo-private.nixosModules.furnace or {})
        lanzaboote.nixosModules.lanzaboote
        ./hw/ugreen_dxp2800.nix
        ./inst/furnace.gensokyo.internal
      ];
    };

    nixosConfigurations.hell = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gensokyo.systems.hell
        (gensokyo-private.nixosModules.hell or {})
        lanzaboote.nixosModules.lanzaboote
        # prime offload onto the dgpu: hardware, so not part of the generic system
        self.nixosModules.nvidia
        nixos-hardware.nixosModules.common-cpu-amd
        nixos-hardware.nixosModules.common-cpu-amd-pstate
        nixos-hardware.nixosModules.common-gpu-amd
        nixos-hardware.nixosModules.common-pc-laptop
        nixos-hardware.nixosModules.common-pc-laptop-ssd
        ./hw/asus_x13_flow.nix
        ./inst/hell.gensokyo.internal
      ];
    };

    nixosConfigurations.library = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gensokyo.systems.library
        (gensokyo-private.nixosModules.library or {})
        lanzaboote.nixosModules.lanzaboote
        ./hw/library.nix
        ./inst/library.gensokyo.internal
      ];
    };

    nixosConfigurations.magic = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gensokyo.systems.magic
        (gensokyo-private.nixosModules.magic or {})
        lanzaboote.nixosModules.lanzaboote
        ./hw/magic.nix
        ./inst/magic.gensokyo.internal
      ];
    };

    nixosConfigurations.mausoleum = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gensokyo.systems.mausoleum
        (gensokyo-private.nixosModules.mausoleum or {})
        ./hw/mausoleum.nix
        ./inst/mausoleum.gensokyo.internal
      ];
    };

    nixosConfigurations.sea = lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gensokyo.systems.sea
        (gensokyo-private.nixosModules.sea or {})
        lanzaboote.nixosModules.lanzaboote
        nixos-hardware.nixosModules.dell-xps-13-9310
        ./hw/dell_xps_13_9310.nix
        ./inst/sea.gensokyo.internal
      ];
    };

    # littledevil (oracle cloud VM.Standard.A1.Flex + local test variants)

    # base
    littledevil.aarch64.nixosConfigurations.base-bootstrap = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ self.overlays.default ]; }
        ldModules.bootstrap
        self.nixosModules.server
        { nixpkgs.crossSystem.system = "aarch64-linux"; }
      ];
    };

    littledevil.x86_64.nixosConfigurations.base-bootstrap = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ self.overlays.default ]; }
        ldModules.bootstrap
        self.nixosModules.server
      ];
    };

    littledevil.aarch64.nixosConfigurations.base-live = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ self.overlays.default ]; }
        ldModules.live
        ldModules.bootstrap
        self.nixosModules.server
        { nixpkgs.crossSystem.system = "aarch64-linux"; }
      ];
    };

    littledevil.x86_64.nixosConfigurations.base-live = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ self.overlays.default ]; }
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
        { nixpkgs.overlays = [ self.overlays.default ]; }
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
        { nixpkgs.overlays = [ self.overlays.default ]; }
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
        { nixpkgs.overlays = [ self.overlays.default ]; }
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
        { nixpkgs.overlays = [ self.overlays.default ]; }
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

    # opentofu with tf/'s providers; the devShell below and `make test_tf` share
    # it, and test_tf runs on a runner of each arch
    packages.x86_64-linux.tofu = tofuWith pkgs;
    packages.aarch64-linux.tofu = tofuWith nixpkgs.legacyPackages.aarch64-linux;

    devShells.x86_64-linux.littledevil = pkgs.mkShell {
      packages = with pkgs; [
        bruno
        libvirt
        m4
        oci-cli
        wireshark
        wrangler
        zap
        self.packages.x86_64-linux.tofu
      ];

      # the credentials are the owner's; the shell is still useful without them
      shellHook = "[ -r secret/credentials.sh ] && . secret/credentials.sh";
    };

    # iso derivations
    nixosConfigurations.iso-minimal = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ self.overlays.default ]; }
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
        { nixpkgs.overlays = [ self.overlays.default ]; }
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-gnome.nix"
        self.nixosModules.base
        ./sys/livecd.nix
      ];
    };

    nixosConfigurations.gensokyo-recovery = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ self.overlays.default ]; }
        {
          networking.hostName = "gensokyo-recovery";
          networking.hostId = lib.mkDefault "00000000";
        }
        self.nixosModules.base
        ./sys/minimal.nix
        ./sys/recovery.nix
      ];
    };

    # flake templates: nix flake init -t github:warmdarksea/nornpkgs#rust-hello

    templates.llm-hello = {
      path = ./template/llm-hello;
      description = "llama-server on a gguf read straight out of the store, under a transient systemd unit";
      welcomeText = "# llm-hello\nbuild: make build  run: make run  test: make test";
    };

    templates.coq-hellovst = {
      path = ./template/coq-hellovst;
      description = "coq + VST/CompCert: a C fibonacci program verified end to end (needs unfree CompCert)";
      welcomeText = "# coq-hellovst\nproofs: nix flake check  binary: nix run  axioms: nix develop --command make audit\nin the devshell: make (proofs)  make run  make smoke  make audit";
    };

    templates.lean4-hello = {
      path = ./template/lean4-hello;
      description = "lean 4 hello world (nix build + lean devshell)";
      welcomeText = "# lean4-hello\nbuild: make build  run: make run  test: make test";
    };

    templates.lean4-hellomath = {
      path = ./template/lean4-hellomath;
      description = "lean 4 proofs with mathlib; building type-checks them";
      welcomeText = "# lean4-hellomath\nbuild (= check the proofs): make build  run: make run  test: make test";
    };

    templates.py-hello = {
      path = ./template/py-hello;
      description = "python hello world (nix build + pytest devshell)";
      welcomeText = "# py-hello\nbuild: make build  run: make run  test: make test\njupyter (sandboxed, needs podman): make start_jupyter / make stop_jupyter";
    };

    templates.py-hellotorch = {
      path = ./template/py-hellotorch;
      description = "python + torch gpu matmul (builds without a gpu; running needs one)";
      welcomeText = "# py-hellotorch\nbuild: make build  run (needs gpu): make run  test: make test\njupyter (sandboxed, torch kernel): make start_jupyter / make stop_jupyter";
    };

    templates.rust-hello = {
      path = ./template/rust-hello;
      description = "rust hello world (nix build + rust devshell)";
      welcomeText = "# rust-hello\nbuild: make build  run: make run  test: make test\njupyter (sandboxed, evcxr kernel): make start_jupyter / make stop_jupyter";
    };

    templates.rust-hellocuda = {
      path = ./template/rust-hellocuda;
      description = "rust + cuda saxpy via runtime nvrtc (builds without a gpu; running needs one)";
      welcomeText = "# rust-hellocuda\nbuild: make build  run (needs gpu): make run  test: make test\njupyter (sandboxed, evcxr + cuda kernel): make start_jupyter / make stop_jupyter";
    };

    # reclaims the multi-GB checkouts lib.fetchModel leaves behind: a converted
    # gguf holds no reference to its source, so the checkout is dead weight the
    # moment you have the format you wanted.
    #   nix run .#gc-model-sources -- --dry-run /nix/store/...-f16.gguf
    packages.x86_64-linux.gc-model-sources = (modelLib pkgs).gc-model-sources;

    # boot tests: checks.<system>.boot-<host> boots the generic system as a
    # NixOS test VM on a host of that system and waits for its default target.
    # eientei is i686 and has none.
    checks = let
      bootTestHosts = {
        x86_64-linux = builtins.attrNames (removeAttrs self.nixosModules.gensokyo.systems [ "eientei" "littledevil" ]);
        aarch64-linux = [ "littledevil" ];
      };
      bootTest = hostPkgs: name: hostPkgs.testers.runNixOSTest {
        name = "boot-${name}";
        # the systems set nixpkgs.overlays and nixpkgs.config themselves
        node.pkgsReadOnly = false;
        nodes.machine = { config, lib, ... }: {
          imports = [ self.nixosModules.gensokyo.systems.${name} ];
          virtualisation.memorySize = 2048;
          virtualisation.cores = 2;
          # the instance side of the VM
          system.stateVersion = lib.mkDefault config.system.nixos.release;
        };
        testScript = ''
          machine.start()
          machine.wait_for_unit("multi-user.target")
          target = machine.succeed("systemctl get-default").strip()
          machine.wait_for_unit(target)
          failed = machine.execute("systemctl list-units --state=failed --no-legend --plain")[1].strip()
          print(f"${name}: reached {target}" + (f", failed units:\n{failed}" if failed else ", no failed units"))
        '';
      };
    in lib.mapAttrs (hostSystem: names:
      lib.genAttrs' names (name: lib.nameValuePair "boot-${name}" (bootTest nixpkgs.legacyPackages.${hostSystem} name))
      // lib.optionalAttrs (hostSystem == "x86_64-linux") {
        # Regression guard for the transformers pin in lib/models.nix. llama.cpp
        # rejects any BPE tokenizer whose digest is missing from its table, and
        # transformers 5.x shifts that digest for every LlamaTokenizerFast model --
        # a class that includes deepseek-llm, deepseek-coder and their descendants,
        # while leaving GPT2/Qwen2 tokenizers alone. So pick a llama-tokenizer
        # model, and convert vocab-only: no weights are fetched or read, which puts
        # the whole check at a few MB and a couple of seconds.
        llama-tokenizer =
          ((modelLib pkgs).fetchHuggingFace {
            src = "hf:deepseek-ai/deepseek-coder-1.3b-instruct@e063262dac8366fc1f28a4da0ff3c50ea66259ca";
            files = [ "*.json" ];
            hash = "sha256-Zu8WFs3xBEEpMuccy3A27iCGAxE4XFwOM3lD282DSaA=";
          }).gguf.convert { vocabOnly = true; };
      }) bootTestHosts;

    # Gearmulator: classic VA synths & sound modules (Access Virus, Waldorf
    # microQ/XT, Nord Lead 2x, JP-8000, MT-32/Sound Canvas) as audio plugins.
    # pkgs/gearmulator is written nixpkgs-style so it can be upstreamed as-is.
    packages.x86_64-linux.gearmulator = nornpkgs.gearmulator;

    # The same plugins and lsp-plugins from the glibc-2.40 pin (pkgsCompat in
    # the let above), for hosts whose process runs an older libc - the Bitwig
    # flatpak. Harmless in newer-glibc hosts, so the home profiles link these.
    packages.x86_64-linux.gearmulator-compat = pkgsCompat.callPackage ./pkgs/gearmulator { };
    packages.x86_64-linux.lsp-plugins-compat = pkgsCompat.lsp-plugins;

    # OpenUtau's DAW integration plugin (VST3/CLAP/VST2 + the bridge-host
    # conformance harness), from our OpenUtau fork's openutau-vst branch.
    # Built from the compat pin for the same Bitwig-flatpak reason.
    packages.x86_64-linux.openutau-bridge = pkgsCompat.callPackage ./pkgs/openutau-bridge { };

    # NanoKVM boot-control tooling.
    packages.x86_64-linux.uefi_trampoline =
      pkgs.callPackage "${uefiTrampolineSrc}/default.nix" { }; # .override { bootId = N; }
    packages.x86_64-linux.nanokvm = nornpkgs.nanokvm;
    packages.x86_64-linux.nanokvmctl = nornpkgs.nanokvmctl;

    packages.x86_64-linux.gpu-timeshare = nornpkgs.gpu-timeshare;

    # slopbooru: the booru (also as release binaries for linux and windows),
    # and its fleet as a timeshare.toml (every model a child process of
    # timeshare, for a machine without the module)
    packages.x86_64-linux.slopbooru = nornpkgs.slopbooru;
    packages.x86_64-linux.slopbooru-release = (slopbooruFor pkgs).release;
    packages.x86_64-linux.slopbooru-fleet = nornpkgs.slopbooru-fleet.timeshare-toml;

    images.gensokyo-recovery =
      self.nixosConfigurations.gensokyo-recovery.config.system.build.image;
    };
}
