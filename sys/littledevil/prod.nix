{ config, pkgs, lib, ... }: {
  boot.supportedFilesystems = [ "zfs" ];

  # the real hostId lives in gensokyo-private.nixosModules.littledevil-prod
  networking.hostId = lib.mkDefault "00000000";
  networking.hostName = "littledevil-prod";

  fileSystems."/data" = {
    device = "comb";
    fsType = "zfs";
    options = [ "nofail" ];
  };
  fileSystems."/data/postgres" = {
    device = "comb/postgres";
    fsType = "zfs";
    options = [ "nofail" ];
  };
  fileSystems."/data/minecraft" = {
    device = "comb/minecraft";
    fsType = "zfs";
    options = [ "nofail" ];
  };

  services.postgresql.dataDir = "/data/postgres/postgres${config.services.postgresql.package.psqlSchema}";

  # services.vector = {
  #   enable = true;
  #   journaldAccess = true;
  #   validateConfig = false;

  #   settings = {
  #     sources.journal = {
  #       type = "journald";
  #     };

  #     sinks.grafana_loki = {
  #       type = "loki";
  #       inputs = [ "journal" ];
  #       endpoint = "\${LOKI_ENDPOINT}";
  #       encoding.codec = "json";

  #       auth = {
  #         strategy = "basic";
  #         user = "\${GRAFANA_USER}";
  #         password = "\${GRAFANA_LOKI_KEY}";
  #       };

  #       labels = {
  #         host = "littledevil-prod";
  #         service_name = "{{ SYSLOG_IDENTIFIER }}";
  #       };
  #     };
  #   };
  # };

  # # Load the API key from your secrets file into the Vector service
  # systemd.services.vector.serviceConfig.EnvironmentFile = [
  #   "/var/secret/grafana/env"
  # ];

  services.alloy = {
    enable = true;
    environmentFile = "/var/secret/grafana/env";
  };

  environment.etc."alloy/config.alloy".text = ''
    loki.write "grafana" {
      endpoint {
        url = env("LOKI_ENDPOINT") + "/loki/api/v1/push"

        basic_auth {
          username = env("GRAFANA_USER")
          password = env("GRAFANA_LOKI_KEY")
        }
      }
    }

    loki.source.journal "journal" {
    forward_to = [loki.write.grafana.receiver]
    labels     = { host = "littledevil-prod" }
    }
  '';
  systemd.services.alloy.serviceConfig = {
    SupplementaryGroups = [ "systemd-journal" ];
  };

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

  # note: services.minecraft-servers.dataDir is set in the minecraft module
  # (only the aarch64 oci-live imports nix-minecraft, which declares it)

  systemd.tmpfiles.rules = [
    #"d /data 0755 root root -"
    "d ${config.services.postgresql.dataDir} 0750 postgres postgres -"
    "d /data/akkoma 0750 akkoma akkoma -"
    "L+ /var/lib/akkoma - - - - /data/akkoma"
    "d /data/minecraft 0750 minecraft minecraft -"
  ];

  nixpkgs.config.allowUnfree = true;
}
