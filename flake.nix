{
  description = "NixOS VM — multi-format image builds";

  inputs = {
    #nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #nixpkgs.url = "path:/home/clownpiece/src/nixpkgs"
    #nixpkgs.url = "git+file:///workspace/littledevil/nixpkgs";
    #nixpkgs.url = "path:/workspace/nix-cross/src/nixpkgs";
    nixpkgs.url = "git+file:///home/clownpiece/src/nixpkgs?ref=littledevil-prod";
    nix-minecraft.url = "github:Infinidoge/nix-minecraft";
  };

  outputs = inputs@{ self, nixpkgs, nix-minecraft, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      crossPkgs = import nixpkgs {
        localSystem.system = "${system}";
        crossSystem.system = "aarch64-linux";
      };
      lib = pkgs.lib;

      # bootstrap is for boot volumes and ssh
      # live is for running the actual services (e.g. akkoma)
      # prod is for hooking up to external services (e.g. grafana)

      nixosModules.bootstrap = { config, pkgs, lib, ... }: {
        # lets us build this derivation standalone, with no bootloader
        boot.isContainer = lib.mkDefault true;

        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 ];
        };

        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = "prohibit-password";
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
          };
        };

        users.users.root.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted"
        ];

        #environment.systemPackages = with pkgs; [
        #  tcpdump
        #];

        system.stateVersion = "24.11";
      };

      nixosModules.live_test = { config, pkgs, lib, ... }: {
        fileSystems."/data" = {
          device = "/dev/disk/by-label/REDACTED";
          fsType = "ext4";
        };

          services.nginx = {
            enable = true;
            virtualHosts."_" = {
              listen = [{ addr = "0.0.0.0"; port = 4000; }];
              locations."/" = {
                return = ''200 "it works\n"'';
                extraConfig = ''
                  default_type text/plain;
                '';     
              };
            };
          };
      };

      nixosModules.live = { config, pkgs, lib, ... }: {
        services.postgresql = {
          enable = true;
          package = pkgs.postgresql_18;
          #ensureDatabases = [ "test" ];
          #ensureUsers = [
          #  {
          #    name = "test";
          #    ensureDBOwnership = true;
          #  }
          #];
          authentication = lib.mkOverride 10 ''
            local all postgres          peer
            local all akkoma            peer
            local all all               scram-sha-256
            host  all all 0.0.0.0/32  scram-sha-256
            host  all all ::1/128       scram-sha-256
            host  all all 0.0.0.0/0     reject
            host  all all ::/0          reject
          '';

          ensureDatabases = [ "akkoma" ];
          ensureUsers = [
            {
              name = "akkoma";
              ensureClauses = {
                login = true;
                superuser = false;
                createdb = false;
                createrole = false;
              };
            }
            # {
            #   name = "synapse";
            #   ensureClauses = {
            #     login = true;
            #     superuser = false;
            #     createdb = false;
            #     createrole = false;
            #   };
            # }
          ];
        };

        services.nginx = {
          enable = true;
          virtualHosts."akkoma" = {
            listen = [{ addr = "0.0.0.0"; port = 80; }];
            locations."/" = {
              return = ''200 "it works\n"'';
              extraConfig = ''
                default_type text/plain;
              '';
            };
          };
        };

        systemd.services.akkoma-initdb.serviceConfig.User = "postgres";
        systemd.services.akkoma-config.serviceConfig = {
          User = "akkoma";
          Group = "akkoma";
        };
        services.akkoma = {
          enable = true;

          # workaround: this is kind of broken and i cannot get it to work
          initDb.enable = true; 
          initDb.username = lib.mkForce "postgres";
          #initDb.password = {
          #  _secret = "/var/secret/akkoma/dbpassword";
          #};
          frontends = {};
          extraStatic = {
            "index.html" = pkgs.writeText "index.html" ''
            <html>backend is working</html>
            '';
          };

          config = lib.recursiveUpdate {
            ":pleroma" = {
              ":instance" = rec {
                name = "little devil club";
                description = "this is (currently) a single-person instance operated by @norn@littledevil.club";
                #short_description = description;
                email = "norn@littledevil.org";
                registration_open = false;
              };

              ":http".proxy_url = "http://0.0.0.0:40000";
              ":media_proxy" = {
                enabled = true;
                base_url = "https://ap.littledevil.club";
              };

              "Pleroma.Repo" = {
                adapter = (pkgs.formats.elixirConf { }).lib.mkRaw "Ecto.Adapters.Postgres";
                socket_dir = "/run/postgresql";
                username = "akkoma";
                database = "akkoma";
                #password = { _secret = "/var/secret/akkoma/dbpassword"; };
              };

              "Pleroma.Upload" = {
                uploader = (pkgs.formats.elixirConf {}).lib.mkRaw "Pleroma.Uploaders.S3";
                base_url = "https://lddn3.littledevil.org";
              };
              "Pleroma.Uploaders.S3" = {
                bucket = "littledevil-prod1";
                bucket_namespace = "";
                truncated_namespace = "";
              };

              "Pleroma.Web.Endpoint" = {
                url.host = "ap.littledevil.club";
                http.port = 4000;
                http.ip = "0.0.0.0";
              };
              "Pleroma.Web.WebFinger" = {
                domain = "littledevil.club";
              };
            };
            
            ":ex_aws".":s3" = {
              access_key_id = { _secret = "/var/secret/akkoma/r2_access_key"; };
              secret_access_key = { _secret = "/var/secret/akkoma/r2_secret_key"; };
              host = "***REMOVED***.r2.cloudflarestorage.com";
              region = "auto";
            };
          } {
            ":pleroma"."Pleroma.Web.Endpoint".secret_key_base = { _secret = "/var/secret/akkoma/pleroma_web_endpoint_secret_key_base"; };
            ":pleroma"."Pleroma.Web.Endpoint".signing_salt = { _secret = "/var/secret/akkoma/pleroma_web_endpoint_signing_salt"; };
            ":pleroma"."Pleroma.Web.Endpoint".live_view.signing_salt = { _secret = "/var/secret/akkoma/pleroma_web_endpoint_live_view_signing_salt"; };
            ":web_push_encryption".":vapid_details".private_key = { _secret = "/var/secret/akkoma/web_push_encryption_vapid_details_private_key"; };
            ":web_push_encryption".":vapid_details".public_key = { _secret = "/var/secret/akkoma/web_push_encryption_vapid_details_public_key"; };
            ":joken".":default_signer" = { _secret = "/var/secret/akkoma/joken_default_signer"; };
          };
        };

        #services.matrix-synapse = {
        #  enable = true;
        #};

        #services.znc = {
        #  enable = true;
        #};

        environment.systemPackages = with pkgs; [
          tcpdump
        ];

        networking.firewall.allowedTCPPorts = [ 80 ];
      };

      nixosModules.prod = { config, pkgs, lib, ... }: let
        # Your Grafana Cloud Loki user ID (the number, not your email)
        grafanaUser = "1500402";

        # Grafana Cloud Loki push endpoint
        lokiEndpoint = "https://logs-prod-042.grafana.net";
      in {
        fileSystems."/data" = {
          device = "/dev/disk/by-label/REDACTED";
          fsType = "ext4";
        };

        services.postgresql.dataDir = "/data/postgres/postgres${config.services.postgresql.package.psqlSchema}";

        services.vector = {
          enable = true;
          journaldAccess = true;
          validateConfig = false;

          settings = {
            sources.journal = {
              type = "journald";
            };

            sinks.grafana_loki = {
              type = "loki";
              inputs = [ "journal" ];
              endpoint = lokiEndpoint;
              encoding.codec = "json";

              auth = {
                strategy = "basic";
                user = grafanaUser;
                password = "\${GRAFANA_LOKI_KEY}";
              };

              labels = {
                host = "littledevil-prod";
                service_name = "{{ SYSLOG_IDENTIFIER }}";
              };
            };
          };
        };

        # Load the API key from your secrets file into the Vector service
        systemd.services.vector.serviceConfig.EnvironmentFile = [
          "/var/secret/grafana/env"
        ];

        nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
          "cloudflare-warp"
          "cloudflare-warp-headless"
          "cloudflare-warp-headless-2025.10.186.0"
        ];

        services.cloudflared = {
          enable = true;
          tunnels."littledevil-prod" = {
            credentialsFile = "/var/secret/cf/tunnel-littledevil-prod.json";
            default = "http_status:404";
            ingress = {
              "ap.littledevil.club" = "http://localhost:4000";
            };
          };
        };

        services.cloudflare-warp = {
          enable = true;
          package = pkgs.cloudflare-warp.override { headless = true; };
        };

        services.tailscale = {
          enable = true;
          authKeyFile = "/var/secret/tailscale/authkey";
        };

        services.minecraft-servers.dataDir = "/data/minecraft";

        systemd.tmpfiles.rules = [
          #"d /data 0755 root root -"
          "d ${config.services.postgresql.dataDir} 0750 postgres postgres -"
          "d /data/akkoma 0750 akkoma akkoma -"
          "L+ /var/lib/akkoma - - - - /data/akkoma"
          "d /data/minecraft 0750 minecraft minecraft -"
        ];

        nixpkgs.config.allowUnfree = true;
      };

      nixosModules.minecraft = { config, pkgs, lib, ... }: {
        #nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];
        imports = [ nix-minecraft.nixosModules.minecraft-servers ];
        services.minecraft-servers = {
          enable = true;
          eula = true;
          openFirewall = true;
          servers.vanilla = {
            enable = true;
            jvmOpts = "-Xmx4G -Xms2G";

            # Specify the custom minecraft server package
            package = nix-minecraft.packages.aarch64-linux.vanilla-server;
          };
        };
      };

      nixosModules.libvirt = { config, pkgs, lib, ... }: {
        system.nixos.label = "libvirt";
        boot.isContainer = false;
        boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" ];

        boot.loader.grub = lib.mkForce {
          enable = true;
          device = "/dev/vda";
        };

        fileSystems."/" = lib.mkForce {
          device = "/dev/vda1";
          fsType = "ext4";
        };

        # QEMU guest agent for IP reporting
        services.qemuGuest.enable = true;

        networking.interfaces.eth0 = {
          useDHCP = false;
          ipv4.addresses = [ {
            address = "0.0.0.0";
            prefixLength = 24;
          } ];
        };
        networking.defaultGateway = "0.0.0.0";
        networking.nameservers = [ "0.0.0.0" ];  # or whatever your DNS is
      };

      nixosModules.oci = { config, lib, pkgs, ... }: {
        system.nixos.label = "oci";

        boot.isContainer = lib.mkForce false;
        #boot.loader.efi.canTouchEfiVariables = true;
        #networking.useHostResolvConf = false;

        # ---------- Boot / kernel ----------
        # boot.kernelParams = [
        #   "console=ttyS0" # enable serial console
        #   #"console=tty1"
        # ];
        services.cloud-init.enable = true;
        #system.build.OCIImage.memSize = lib.mkDefault 4096;
        # system.build.OCIImage = lib.mkForce (import ./make-disk-image.nix {
        #   inherit config lib pkgs;
        #   inherit (config.virtualisation) diskSize;
        #   name = "oci-image";
        #   configFile = "${nixpkgs}/nixos/modules/virtualisation/oci-config-user.nix";
        #   format = "qcow2";
        #   partitionTableType = "efi";
        #   memSize = 4096;
        # });
      };

    in rec {
      # base
      packages.aarch64.nixosConfigurations.base-bootstrap = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixosModules.bootstrap
          { nixpkgs.crossSystem.system = "aarch64-linux"; }
        ];
      };

      packages.x86_64.nixosConfigurations.base-bootstrap = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixosModules.bootstrap
        ];
      };

      packages.aarch64.nixosConfigurations.base-live = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixosModules.live
          nixosModules.bootstrap
          { nixpkgs.crossSystem.system = "aarch64-linux"; }
        ];
      };

      packages.x86_64.nixosConfigurations.base-live = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixosModules.bootstrap
          nixosModules.live
        ];
      };

      # oci
      packages.aarch64.images.oci-bootstrap = packages.aarch64.nixosConfigurations.oci-bootstrap.config.system.build.OCIImage;
      packages.x86_64.images.oci-bootstrap = packages.x86_64.nixosConfigurations.oci-bootstrap.config.system.build.OCIImage;

      packages.aarch64.nixosConfigurations.oci-bootstrap = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixosModules.oci
          nixosModules.bootstrap
          { nixpkgs.crossSystem.system = "aarch64-linux"; }
          "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"     
          {
            oci.efi = lib.mkForce true;
            boot.loader.grub.enable = lib.mkForce false;
            boot.loader.systemd-boot.enable = true;
          }
        ];
      };

      packages.x86_64.nixosConfigurations.oci-bootstrap = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixosModules.oci
          nixosModules.bootstrap
          "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
          {            
            oci.efi = lib.mkForce false;
          }
        ];
      };

      packages.x86_64.nixosConfigurations.oci-live = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixosModules.oci
          nixosModules.live
          nixosModules.prod
          nixosModules.bootstrap
          "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
          {            
            oci.efi = lib.mkForce false;
            systemd.services.akkoma.environment = {
              ERL_FLAGS = "+MIscs 256";
            };
          }
        ];
      };

      packages.aarch64.nixosConfigurations.oci-live = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixosModules.oci
          nixosModules.live
          nixosModules.minecraft
          nixosModules.prod
          nixosModules.bootstrap
          {
            #nixpkgs.buildPlatform = "${system}-linux";
            #nixpkgs.hostPlatform = "aarch64-linux";
            nixpkgs.localSystem.system = "${system}";
            nixpkgs.crossSystem.system = "aarch64-linux";
          }
          "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
          {            
            oci.efi = lib.mkForce true;
            boot.loader.grub.enable = lib.mkForce false;
            boot.loader.systemd-boot.enable = true;
          }
        ];
      };

      # packages.aarch64.nixosConfigurations.base-bootstrap = nixpkgs.lib.nixosSystem {
      #   inherit system;
      #   modules = [
      #     nixosModules.bootstrap
      #     {
      #       #nixpkgs.buildPlatform = "${system}-linux";
      #       #nixpkgs.crossSystem.system = "aarch64-linux";
      #       #nixpkgs.hostPlatform = "aarch64-linux";
      #     }
      #   ];
      # };

      #

      packages.x86_64-linux = {
        akkoma-fe = pkgs.akkoma-fe;
        # akkoma-fe = pkgs.akkoma-fe.overrideAttrs (old: {
        #   postPatch = (old.postPatch or "") + ''
        #     cp ${./config/akkoma-fe.local.json} config/local.json
        #   '';
        # });
        ovmf = pkgs.OVMF.fd;
      };
      packages.aarch64-linux = {
        akkoma-fe = pkgs.akkoma-fe;
        # akkoma-fe = pkgs.akkoma-fe.overrideAttrs (old: {
        #   postPatch = (old.postPatch or "") + ''
        #     cp ${./config/akkoma-fe.local.json} config/local.json
        #   '';
        # });
        ovmf = pkgs.OVMF.fd;
        erlang = let
          crossPkgs = import nixpkgs {
            localSystem.system = "x86_64-linux";
            crossSystem.system = "aarch64-linux";
          };
          erlang = crossPkgs.beamMinimal26Packages.erlang;
        in erlang;
        #pkgs.pkgsCross.aarch64-multiplatform.beam.packages.erlang_26.erlang;
        akkoma = crossPkgs.akkoma;
        webkit = crossPkgs.gtk3;
        erlang28 = crossPkgs.erlang;
        rebar3 = crossPkgs.beamMinimal26Packages.rebar3;
      };
      nixosConfigurations = {
        # bootstrap = nixpkgs.lib.nixosSystem {
        #   inherit system;
        #   modules = [ nixosModules.bootstrap ];
        # };
        # bootstrap-aarch64 = nixpkgs.lib.nixosSystem {
        #   inherit system;
        #   modules = [
        #     nixosModules.bootstrap
        #     {
        #       nixpkgs.crossSystem.system = "aarch64-linux";
        #     }
        #   ];
        # };
        # live = nixpkgs.lib.nixosSystem {
        #   inherit system;
        #   modules = [ bootstrap-module live-module ];
        # };
        # libvirt-bootstrap = nixpkgs.lib.nixosSystem {
        #   inherit system;
        #   modules = [ bootstrap-module libvirt-module ];
        # };
        # libvirt-live = nixpkgs.lib.nixosSystem {
        #   inherit system;
        #   modules = [ bootstrap-module live-module libvirt-module ];
        # };
        # oci-bootstrap = nixpkgs.lib.nixosSystem {
        #   inherit system;
        #   modules = [ "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix" bootstrap-module oci-module ];
        # };
        # oci-bootstrap-aarch64 = nixpkgs.lib.nixosSystem {
        #   #system = "aarch64-linux";
        #   inherit system;
        #   modules = [
        #     "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
        #     bootstrap-module
        #     {
        #     nixpkgs.buildPlatform = "x86_64-linux";
        #     nixpkgs.hostPlatform = "aarch64-linux";
        #   }
        #     {
        #       oci.efi = lib.mkForce true;
        #       system.nixos.label = "oci";

        #       boot.isContainer = lib.mkForce false;

        #       # ---------- Boot / kernel ----------
        #       boot.kernelParams = [
        #         #"console=ttyS0" # enable serial console
        #         #"console=tty1"
        #       ];
        #       services.cloud-init.enable = true;
        #     }
        #   ];
        # };
        # oci-live = nixpkgs.lib.nixosSystem {
        #   inherit system;
        #   modules = [ "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix" bootstrap-module live-module oci-module ];
        # };
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          #aliyun-cli
          #awscli2
          #azure-cli
          bruno
          libvirt
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
    };
}
