# imgrec -- image recognition as a service: a fleet of vision models (vllm
# servers plus the pixai tagger) behind one HTTP API, scheduled onto one GPU.
# The program and its design live in the slopbooru repository (imgrec/);
# this is only the service around it. The package is pkgs.imgrec, from the
# overlay (flake.nix pins the repository).
#
# Per-host:
#   services.imgrec = {
#     enable = true;
#     host = "0.0.0.0";        # TLS turns on by itself off loopback
#     openFirewall = true;
#   };
#
# The package's bin/imgrec carries everything a model needs (engine, specs,
# weights manifest) -- the module passes only where things live and where to
# listen. Clients are managed as the service user:
#   sudo -u imgrec imgrec-client add alice     # prints alice's token, once
#   sudo -u imgrec imgrec-client list
# and use it with
#   imgrec submit --server https://HOST:8100 --cacert imgrec.crt --token T pictures/*
# where imgrec.crt is the service's self-signed certificate (tls.certFile
# unset), made on its first start:
#   sudo cat /var/lib/imgrec/tls/imgrec.crt > imgrec.crt
#
# The models want the whole card while they run: stop anything else using
# the GPU (a long-lived llm server) first. Once the queue is empty, the
# last model unloads after `idle` and the card is back to its idle power
# state, with nothing of imgrec's on it.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.imgrec;
  db = "${cfg.dataDir}/imgrec.db";
  loopback = builtins.elem cfg.host [ "127.0.0.1" "::1" "localhost" ];
  selfSigned = cfg.tls.enable && cfg.tls.certFile == null;
  tlsDir = "${cfg.dataDir}/tls";
  certFile = if selfSigned then "${tlsDir}/imgrec.crt" else cfg.tls.certFile;
  keyFile = if selfSigned then "${tlsDir}/imgrec.key" else cfg.tls.keyFile;

  # the client admin command: the same binary, pointed at the service's db
  clientCmd = pkgs.writeShellScriptBin "imgrec-client" ''
    exec ${lib.getExe' cfg.package "imgrec"} client --db ${lib.escapeShellArg db} "$@"
  '';
in
{
  options.services.imgrec = {
    enable = lib.mkEnableOption "imgrec, the image recognition service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.imgrec;
      defaultText = lib.literalExpression "pkgs.imgrec";
      description = ''
        imgrec, bundled with its engine and models: the slopbooru
        repository's `imgrec` attribute (nornpkgs' overlay has it).
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address the API listens on.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8100;
      description = "Port the API listens on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the port (set `host` to something other than loopback too).";
    };

    tls = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = !loopback;
        defaultText = lib.literalMD "on unless `host` is loopback";
        description = ''
          Serve https. A client's token is a password: off this machine it
          should not travel as plain http.
        '';
      };
      certFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          The certificate (PEM), re-read whenever it changes -- a renewal
          needs no restart. The imgrec user must be able to read it and
          the key. null: a self-signed certificate for `tls.hosts`, made on
          the first start in dataDir/tls/imgrec.crt; clients trust it with
          `imgrec submit --cacert`. Delete both files there to remake it.
        '';
      };
      keyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "The certificate's private key (PEM), with `tls.certFile`.";
      };
      hosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = lib.unique ([ config.networking.hostName config.networking.fqdnOrHostName
          "localhost" "127.0.0.1" ] ++ lib.optional (!loopback && cfg.host != "0.0.0.0" && cfg.host != "::") cfg.host);
        defaultText = lib.literalMD "the host name, its fqdn, localhost, 127.0.0.1 and `host`";
        example = [ "library" "library.gensokyo.internal" "10.0.0.2" ];
        description = "Names and addresses the self-signed certificate is valid for.";
      };
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/imgrec";
      description = ''
        The db (answers, jobs, clients), uploaded pictures and their
        downscaled stand-ins, and the runners' logs. Wants disk, not tmpfs.
      '';
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "pixai" "gemma" "llamaguard" ];
      description = "Models to serve; empty is every model the package has a spec for.";
    };

    rotation = lib.mkOption {
      type = lib.types.str;
      default = "2h";
      description = "A busy model gives the card up after this when other models have work waiting.";
    };

    idle = lib.mkOption {
      type = lib.types.str;
      default = "10m";
      description = ''
        A loaded model with no work for this long is stopped, so an empty
        queue leaves the card free to power down; the next job pays the
        model's start (1-2 minutes). "0" keeps models loaded.
      '';
    };

    maxUpload = lib.mkOption {
      type = lib.types.ints.positive;
      default = 256 * 1024 * 1024;
      description = "Largest picture accepted, in bytes.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { IMGREC_MAX_ATTEMPTS = "5"; };
      description = "Extra environment for the service (every flag defaults from IMGREC_<NAME>).";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments to `imgrec serve`.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = (cfg.tls.certFile == null) == (cfg.tls.keyFile == null);
      message = "services.imgrec.tls: certFile and keyFile go together";
    }];
    warnings = lib.optional (!loopback && !cfg.tls.enable)
      "services.imgrec listens on ${cfg.host} without TLS: tokens and pictures cross the network in the clear";

    users.users.imgrec = {
      isSystemUser = true;
      group = "imgrec";
      home = cfg.dataDir;
      # the nvidia device nodes are 0666 on nixos; video covers the rest
      extraGroups = [ "video" "render" ];
    };
    users.groups.imgrec = { };

    systemd.tmpfiles.settings.imgrec = {
      ${cfg.dataDir}.d = { user = "imgrec"; group = "imgrec"; mode = "0750"; };
    } // lib.optionalAttrs selfSigned {
      ${tlsDir}.d = { user = "imgrec"; group = "imgrec"; mode = "0750"; };
    };

    # imgrec itself too, for `imgrec submit` from this machine
    environment.systemPackages = [ clientCmd cfg.package ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.imgrec = {
      description = "imgrec image recognition service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        HOME = cfg.dataDir;
        # vllm, triton, torch and flashinfer all compile and cache kernels
        # here; keeping it across restarts saves minutes per model start
        XDG_CACHE_HOME = "/var/cache/imgrec";
      } // cfg.environment;

      # the self-signed certificate, once; the key never leaves dataDir
      preStart = lib.optionalString selfSigned ''
        ${lib.getExe' cfg.package "imgrec"} cert --if-missing \
          --hosts ${lib.escapeShellArg (lib.concatStringsSep "," cfg.tls.hosts)} \
          --cert ${lib.escapeShellArg certFile} --key ${lib.escapeShellArg keyFile}
      '';

      serviceConfig = {
        ExecStart = lib.escapeShellArgs ([
          (lib.getExe' cfg.package "imgrec") "serve"
          "--db" db
          "--listen" "${cfg.host}:${toString cfg.port}"
          "--rotation" cfg.rotation
          "--idle" cfg.idle
          "--max-upload" (toString cfg.maxUpload)
        ] ++ lib.optionals (cfg.models != [ ]) [ "--models" (lib.concatStringsSep "," cfg.models) ]
          ++ lib.optionals cfg.tls.enable [ "--tls-cert" certFile "--tls-key" keyFile ]
          ++ cfg.extraArgs);
        User = "imgrec";
        Group = "imgrec";
        WorkingDirectory = cfg.dataDir;
        CacheDirectory = "imgrec";
        Restart = "on-failure";
        RestartSec = 10;

        # imgrec stops its runners (each its own process group) on SIGTERM;
        # whatever is left after the timeout gets the SIGKILL
        KillMode = "mixed";
        TimeoutStopSec = 90;

        # no PrivateDevices (the GPU), no MemoryDenyWriteExecute (kernels
        # are jit-compiled)
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
      };
    };
  };
}
