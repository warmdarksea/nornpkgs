{ config, pkgs, lib, ... }: {
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
      host  all all 127.0.0.1/32  scram-sha-256
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
    frontends = {
      primary = {
        package = pkgs.buildPackages.akkoma-fe;
        name = "akkoma-fe";
        ref = "stable";
      };
    };
    #extraStatic = {
    #  "index.html" = pkgs.writeText "index.html" ''
    #    <html>backend is working</html>
    #  '';
    #};

    config = lib.recursiveUpdate {
      ":pleroma" = {
        ":instance" = rec {
          name = "littledevil club";
          description = "just a little bit evil";
          email = "norn@littledevil.org";
          registrations_open = false;
          invites_enabled = true;
        };

        # note: ":http".proxy_url lives in
        # gensokyo-private.nixosModules.littledevil-prod
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
          http.ip = "127.0.0.1";
        };
        "Pleroma.Web.WebFinger" = {
          domain = "littledevil.club";
        };
      };

      # note: the r2 endpoint (":ex_aws".":s3".host) lives in
      # gensokyo-private.nixosModules.littledevil-prod, since it contains
      # the cloudflare account id
      ":ex_aws".":s3" = {
        access_key_id = { _secret = "/var/secret/akkoma/r2_access_key"; };
        secret_access_key = { _secret = "/var/secret/akkoma/r2_secret_key"; };
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
}
