{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
  let
    system = "x86_64-linux";
    pkgs = import inputs.nixpkgs { inherit system; };

    attrsetToTfVars = attrs:
      let
      # Convert a single key-value pair to a tfvars line
      formatValue = name: value:
      if builtins.isString value then
      "${name} = \"${value}\""
      else if builtins.isBool value then
      "${name} = ${if value then "true" else "false"}"
      else if builtins.isInt value || builtins.isFloat value then
      "${name} = ${toString value}"
      else if builtins.isList value then
      "${name} = [${builtins.concatStringsSep ", " (map (v: 
      if builtins.isString v then "\"${v}\"" 
      else toString v) value)}]"
      else
      throw "Unsupported value type for ${name}";
      
      # Map over all the attributes and format them
      lines = builtins.attrNames attrs;
      content = builtins.concatStringsSep "\n" (map (name: formatValue name attrs.${name}) lines);
    in pkgs.writeText "terraform.tfvars" content;

      # Step 2: Define image
      bootstrap-config-module = {
        system.stateVersion = "22.05";
        services.openssh.enable = true;
        users.users.root.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted"
        ];
        #environment.systemPackages = with pkgs; [
        #  mosh
        #];
      };

      #virtualisation.writableStoreUseTmpfs = false;

      live-wireguard-module = {
        environment.systemPackages = with pkgs; [
          mosh
          nmap
          tcpdump
        ];
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
        networking.firewall.allowedUDPPorts = [ 44283 ];
        # don't start it until we copy the keys over
        # systemd.services."wireguard-wg0".enable = false;
        networking.wireguard.interfaces = {
          wg0 = {
            # Determines the IP address and subnet of the server's end of the tunnel interface.
            ips = [ "0.0.0.0/24" ];

            # The port that WireGuard listens to. Must be accessible by the client.
            listenPort = 44283;

            # Path to the private key file.
            #
            # Note: The private key can also be included inline via the privateKey option,
            # but this makes the private key world-readable; thus, using privateKeyFile is
            # recommended.
            privateKeyFile = "/var/lib/wireguard/keys/privkey";

            # 171 207 239 197 160 53
            peers = [
              # bridge
              {
                publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                presharedKeyFile = "/var/lib/wireguard/keys/bridge.psk";
                allowedIPs = [ "0.0.0.0/32" "0.0.0.0/24" ];
              }
              # chireiden
              {
                publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                presharedKeyFile = "/var/lib/wireguard/keys/chireiden.psk";
                allowedIPs = [ "0.0.0.0/32" ];
              }
              # dusk
              {
                publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                presharedKeyFile = "/var/lib/wireguard/keys/dusk.psk";
                allowedIPs = [ "0.0.0.0/32" ];
              }
              # hell
              {
                publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                presharedKeyFile = "/var/lib/wireguard/keys/hell.psk";
                allowedIPs = [ "0.0.0.0/32" ];
              }
            ];
          };
        };
      };

      # Step 3: Deploy
      bootstrap-img-name = "nixos-bootstrap-${system}";
      bootstrap-img = inputs.nixos-generators.nixosGenerate {
        inherit pkgs;
        format = "amazon";
        specialArgs = {
        };
        modules = [
          bootstrap-config-module
          { amazonImage.name = bootstrap-img-name; }
          { virtualisation.diskSize = "auto"; }
        ];
      }; 

      live-config = (inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          bootstrap-config-module
          live-wireguard-module
          "${inputs.nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
          {
          }
        ];
      });
      bootstrap-img-path = "${bootstrap-img}/${bootstrap-img-name}.vhd";

      deploy-shell = pkgs.mkShell {
        packages = [ pkgs.terraform ];
        TF_VAR_bootstrap_img_path = bootstrap-img-path;
        TF_VAR_live_config_path = "${live-config.config.system.build.toplevel}";
      };

      #terraform = pkgs.writeShellScriptBin "terraform" ''
      #  export TF_VAR_bootstrap_img_path="${bootstrap-img-path}"
      #  export TF_VAR_live_config_path="${live-config}"
      #  ${pkgs.terraform}/bin/terraform $@
      #'';

    in
      {
        nixosConfigurations.bootstrap = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ bootstrap-config-module ];
        };
        nixosConfigurations.live = live-config;

        terraformConfigurations.default = attrsetToTfVars {
          bootstrap_img_path = "${bootstrap-img-path}";
          live_config_path = "${live-config.config.system.build.toplevel}";
        };

        packages.${system} = {
          inherit bootstrap-img;
        };
        devShell.${system} = deploy-shell;
      };
}
