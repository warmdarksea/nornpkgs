# imgrec -- image recognition as a service: a fleet of vision models (vllm
# servers plus the pixai tagger) behind one HTTP API, scheduled onto one GPU.
# The program and its design live in the imgrec repository; this is only the
# service around it.
#
# Per-host:
#   services.imgrec = {
#     enable = true;
#     package = pkgs.callPackage "${imgrecSrc}/default.nix" { };
#   };
#
# The package's bin/imgrec has to carry everything a model needs (engine,
# specs, weights manifest) -- the module passes only where things live and
# where to listen. Clients are managed as the service user:
#   sudo -u imgrec imgrec-client add alice     # prints alice's token, once
#   sudo -u imgrec imgrec-client list
# and use it with
#   imgrec submit --server http://HOST:8100 --token T pictures/*
#
# The models want the whole card while they run: stop anything else using
# the GPU (a long-lived llm server) first. imgrec unloads a model only to
# make room for another, so once the queue is empty the last model stays
# loaded (qwen: ~23 GB) until more work arrives or the service stops --
# `systemctl stop imgrec` gives the card back.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.imgrec;
  db = "${cfg.dataDir}/imgrec.db";

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
      description = ''
        imgrec, bundled with its engine: the default.nix at the root of the
        imgrec repository, e.g. `pkgs.callPackage "''${imgrecSrc}/default.nix" { }`.
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
    };

    environment.systemPackages = [ clientCmd ];

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

      serviceConfig = {
        ExecStart = lib.escapeShellArgs ([
          (lib.getExe' cfg.package "imgrec") "serve"
          "--db" db
          "--listen" "${cfg.host}:${toString cfg.port}"
          "--rotation" cfg.rotation
          "--max-upload" (toString cfg.maxUpload)
        ] ++ lib.optionals (cfg.models != [ ]) [ "--models" (lib.concatStringsSep "," cfg.models) ]
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
