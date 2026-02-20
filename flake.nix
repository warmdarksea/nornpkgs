{
  description = "NixOS VM — multi-format image builds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";

      # ---------------------------------------------------------------
      # tercha - Core system derivation (base config, users, services)
      # ---------------------------------------------------------------
      tercha = { config, pkgs, lib, ... }: {
        # --- Networking ---
        networking = {
          hostName = "nixvm";
          useDHCP = true;
          firewall = {
            enable = true;
            allowedTCPPorts = [ 22 ];
          };
        };

        # --- Packages ---
        environment.systemPackages = with pkgs; [
          vim
          htop
          curl
          git
          tmux
        ];

        # --- Locale / Time ---
        time.timeZone = "America/New_York";
        i18n.defaultLocale = "en_US.UTF-8";

        # --- Nix settings ---
        nix = {
          settings = {
            experimental-features = [ "nix-command" "flakes" ];
            auto-optimise-store = true;
          };
          gc = {
            automatic = true;
            dates = "weekly";
            options = "--delete-older-than 30d";
          };
        };

        # --- Users ---
        users.users.admin = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          openssh.authorizedKeys.keys = [
            # TODO: add your SSH public key(s) here
            # "ssh-ed25519 AAAA..."
          ];
        };

        security.sudo.wheelNeedsPassword = false;

        # --- Services ---
        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = "prohibit-password";
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
          };
          extraConfig = ''
            AllowAgentForwarding no
            AllowTcpForwarding yes
            X11Forwarding no
          '';
        };

        system.stateVersion = "24.11";
      };

      # ---------------------------------------------------------------
      # oplawn - System with boot/filesystem (includes tercha)
      # ---------------------------------------------------------------
      oplawn = { modulesPath, ... }: {
        imports = [
          tercha
          (modulesPath + "/profiles/qemu-guest.nix")
        ];

        boot.loader.grub = {
          enable = true;
          device = "/dev/vda";
        };

        fileSystems."/" = {
          device = "/dev/vda1";
          fsType = "ext4";
        };
      };

    in rec
    {
      # ---------------------------------------------------------------
      # Image outputs — build with:
      #   nix build .#qcow2
      #   nix build .#amazon
      #   nix build .#gce
      # ---------------------------------------------------------------
      packages.${system} =
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # QCOW2 disk image configuration
          qcow2System = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              oplawn
              ({ config, lib, pkgs, modulesPath, ... }: {
                imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

                # Build a disk image
                system.build.qcow2 = import (modulesPath + "/../lib/make-disk-image.nix") {
                  inherit lib config pkgs;
                  diskSize = 8192;
                  format = "qcow2";
                  partitionTableType = "legacy";
                };
              })
            ];
          };

          # Amazon AMI configuration
          amazonSystem = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              tercha
              ({ modulesPath, ... }: {
                imports = [ (modulesPath + "/virtualisation/amazon-image.nix") ];
                ec2.hvm = true;
              })
            ];
          };

          # GCE image configuration
          gceSystem = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              tercha
              ({ modulesPath, ... }: {
                imports = [ (modulesPath + "/virtualisation/google-compute-image.nix") ];
              })
            ];
          };

        in {
          qcow2   = qcow2System.config.system.build.qcow2;
          amazon  = amazonSystem.config.system.build.amazonImage;
          gce     = gceSystem.config.system.build.googleComputeImage;
        };

      # ---------------------------------------------------------------
      # nixosConfigurations - for building system derivations
      # ---------------------------------------------------------------
      nixosConfigurations = {
        # tercha - base system only (no boot/filesystem)
        tercha = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ tercha ];
        };

        # oplawn - full system with boot/filesystem configuration
        oplawn = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ oplawn ];
        };
      };
    };
}
