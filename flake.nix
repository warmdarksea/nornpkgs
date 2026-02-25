{
  description = "NixOS VM — multi-format image builds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      bootstrap-module = {
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

        # lets us build this derivation standalone
        boot.isContainer = lib.mkDefault true;

        system.stateVersion = "24.11";
      };

      live-module = {
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

        services.akkoma = {
          enable = true;

          config = {
            ":pleroma" = {
              ":instance" = {
                name = "My Akkoma instance";
                description = "More detailed description";
                email = "admin@example.com";
                registration_open = false;
              };

              "Pleroma.Web.Endpoint" = {
                url.host = "ap.ldtest.hell.gensokyo.internal";
              };
              "Pleroma.Upload".base_url = "lddn0.ldtest.hell.gensokyo.internal";
            };
          };
        };

        #services.matrix-synapse = {
        #  enable = true;
        #};

        #services.znc = {
        #  enable = true;
        #};

        networking.firewall.allowedTCPPorts = [ 80 ];
      };

      libvirt-module = {
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

      oci-module = {
        system.nixos.label = "oci";

        boot.isContainer = lib.mkForce false;

        # ---------- Boot / kernel ----------
        # OCI paravirtualized instances use virtio for everything
        boot.initrd.availableKernelModules = [
          "virtio_pci"
          "virtio_blk"
          "virtio_scsi"
          "virtio_net"
          "virtio_mmio"
        ];

        # boot.loader.grub = lib.mkForce {
        #   enable = true;
        #   # For qcow2 images built by nixos-generators / system.build.images.qemu
        #   device = "/dev/vda";
        #   #efiSupport = false;
        # };

        # fileSystems."/" = lib.mkForce {
        #   device = "/dev/vda1";
        #   fsType = "ext4";
        # };

        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = false;  # OCI has no NVRAM

        fileSystems."/boot/efi" = lib.mkForce {
          device = "/dev/vda1";  # ESP partition
          fsType = "vfat";
        };

        fileSystems."/" = lib.mkForce {
          device = "/dev/vda2";   # root is now partition 2
          fsType = "ext4";
        };

        # ---------- Cloud-init ----------
        # OCI uses cloud-init to inject SSH keys at launch time.
        # This is critical — without it you'll have no way to SSH in
        # unless you bake keys into the image (which you already do,
        # but cloud-init lets OCI's metadata service work too).
        services.cloud-init = {
          enable = true;
          network.enable = true;
          settings = {
            system_info = {
              distro = "nixos";
              default_user = {
                name = "root";
              };
            };
            # OCI metadata endpoint
            datasource_list = [ "Oracle" "None" ];
            datasource.Oracle = {};
          };
        };

        # ---------- Networking ----------
        # Let cloud-init / DHCP handle it — OCI VCN assigns IPs via DHCP
        networking.useDHCP = true;
        #systemd.network.enable = false;
        networking.useNetworkd = true;

        # Don't wait forever for a network interface name we don't know yet
        networking.usePredictableInterfaceNames = true;
      };

    in rec {
      packages.${system} = {
        akkoma-fe = pkgs.akkoma-fe;
        # akkoma-fe = pkgs.akkoma-fe.overrideAttrs (old: {
        #   postPatch = (old.postPatch or "") + ''
        #     cp ${./config/akkoma-fe.local.json} config/local.json
        #   '';
        # });
      };
      nixosConfigurations = {
        bootstrap = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ bootstrap-module ];
        };
        live = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ bootstrap-module live-module ];
        };
        libvirt-bootstrap = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ bootstrap-module libvirt-module ];
        };
        libvirt-live = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ bootstrap-module live-module libvirt-module ];
        };
        oci-bootstrap = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ bootstrap-module oci-module ];
        };
        oci-live = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ bootstrap-module live-module oci-module ];
        };
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          #aliyun-cli
          #awscli2
          #azure-cli
          libvirt
          oci-cli
          wrangler
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
      };
    };
}
