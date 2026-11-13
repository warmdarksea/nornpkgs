# gensokyo-agent — rootless podman sandbox for coding agents (claude, codex, opencode).
# Import on each host; everything is derived from that host's config.
#
# Per-host:
#   gensokyo-agent = { enable = true; user = "clownpiece"; };
#   nixpkgs.config = { cudaSupport = true; };
# (no cudaCapabilities: the default set is what cache.nixos-cuda.org builds;
# the gencode flags below therefore cover every supported arch)
# The GPU side of the sandbox (cudatoolkit, the driver's userspace, nvidia-uvm,
# the nvcc flags) follows nixpkgs.config.cudaSupport, so a host without it --
# and the CI build, which sets cudaSupport = !gensokyo.ci -- gets a CPU-only
# sandbox. The agents themselves are large leaves CI never runs, so
# gensokyo.ci leaves them out as well.
#
# One-time, as the user (rootless secrets are per-user, and per podman host):
#   gensokyo-agent claude setup-token            # browser flow, prints a 1-year token
#   printf %s "$token" | podman secret create claude-oauth-token -
# The sandbox keeps no home between runs, so that secret is the login.
#
# Usage:
#   gensokyo-agent                        claude, permissions skipped
#   gensokyo-agent codex                  any command in the sandbox
#   AGENT_CMD="opencode" gensokyo-agent   change the default
{ config, pkgs, lib, ... }:
let
  cfg = config.gensokyo-agent;
  u = config.users.users.claude;
  g = config.users.groups.agent;
  cudaSupport = pkgs.config.cudaSupport or false;
  cuda = pkgs.cudaPackages;
  gencode = lib.concatStringsSep " " cuda.flags.gencode;
  uid = toString u.uid;
  gid = toString g.gid;
  kvm = toString config.ids.gids.kvm;
  home = "/home/agent";             # container-only, and gone with the container

  env = pkgs.buildEnv {
    name = "gensokyo-agent-env";
    paths = with pkgs; [
      nix gitMinimal bashInteractive
      coreutils findutils gnused gnugrep gawk diffutils which file tree less
      curl wget netcat nmap
      procps util-linux jq ripgrep fd
    ] ++ lib.optionals (!config.gensokyo.ci) [
      claude-code codex opencode
    ] ++ lib.optionals cudaSupport [
      cuda.cudatoolkit
      config.hardware.nvidia.package.bin
    ];
  };

  # what the sandbox takes from this host's store, under one name that is the
  # same on every host (bound read-only at the same path): nothing the wrapper
  # passes to podman, and nothing in the rootfs, names a store path, so a
  # sandbox started from another machine gets this host's tools
  hostPath = "/etc/gensokyo-agent";
  hostDir = pkgs.linkFarm "gensokyo-agent-host" ({
    inherit env;
    nixpkgs = pkgs.path;
    "ca-bundle.crt" = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    "nix.conf" = config.environment.etc."nix/nix.conf".source;
    "registry.json" = config.environment.etc."nix/registry.json".source;
  } // lib.optionalAttrs cudaSupport {
    cc = cuda.backendStdenv.cc;
  });

  nss = pkgs.dockerTools.fakeNss.override {
    extraPasswdLines = [ "claude:x:${uid}:${gid}::${home}:/bin/sh" ];
    extraGroupLines = [ "agent:x:${gid}:" ];
  };

  # real directories at the top level: podman populates /etc before anything is
  # mounted, so only the leaves may be symlinks, and they dangle until ${hostPath} is bound
  rootfs = pkgs.runCommand "gensokyo-agent-rootfs" { } ''
    mkdir -p $out/{etc/nix,bin,usr/bin,tmp} $out${home}
    cp -rL ${nss}/etc/. $out/etc/
    ln -s ${hostPath}/nix.conf ${hostPath}/registry.json $out/etc/nix/
    ln -s ${hostPath}/env/bin/sh $out/bin/sh
    ln -s ${hostPath}/env/bin/env $out/usr/bin/env
    printf "[user]\n\tname = Claude\n\temail = claude@anthropic.com\n" > $out/etc/gitconfig
  '';

  # the one secret every sandbox gets; from `claude setup-token`, never
  # ANTHROPIC_API_KEY, that bills API credits
  token = { secret = "claude-oauth-token"; target = "CLAUDE_CODE_OAUTH_TOKEN"; };

  runArgs = [
    "--rm" "--log-driver" "none"
    # catatonit as pid 1. without it the agent itself is pid 1, and pid 1
    # in a pid namespace is the only process that can reap orphans -- so
    # anything the agent daemonises (a jupyter server, a dev server, any
    # nohup'd thing) is reparented to a process that never calls wait()
    # and stays a zombie for the life of the sandbox. zombies still answer
    # `kill -0`, which makes a pidfile look live long after the process
    # has gone. nixpkgs' podman points init_path at catatonit already.
    "--init"
    "--uidmap" "0:0:1" "--uidmap" "${uid}:@${uid}:1"
    "--gidmap" "0:0:1" "--gidmap" "${gid}:@${gid}:1" "--gidmap" "${kvm}:@${kvm}:1"
    "--user" "${uid}:${gid}" "--group-add" kvm
    "--device" "/dev/kvm"
    "--mount" "type=tmpfs,destination=/tmp,tmpfs-mode=1777,tmpfs-size=8g"
    "-v" "/nix:/nix:ro"
    "-v" "/nix/var/nix/daemon-socket/socket:/nix/var/nix/daemon-socket/socket"
    "-v" "${hostPath}:${hostPath}:ro"
    "-v" "/run/opengl-driver:/run/opengl-driver:ro"
    "-e" "HOME=${home}"
    "-e" "IS_SANDBOX=1"
    "-e" "PATH=${hostPath}/env/bin"
    "-e" "NIX_PATH=nixpkgs=${hostPath}/nixpkgs"
    "-e" "SSL_CERT_FILE=${hostPath}/ca-bundle.crt"
    "-e" "LD_LIBRARY_PATH=/run/opengl-driver/lib"
  ] ++ lib.optionals cudaSupport [
    "--device" "/dev/nvidiactl" "--device" "/dev/nvidia0"
    "--device" "/dev/nvidia-uvm" "--device" "/dev/nvidia-uvm-tools"
    "-e" "CUDA_PATH=${hostPath}/env"
    "-e" "NVCC_PREPEND_FLAGS=-ccbin ${hostPath}/cc/bin/g++ -I${hostPath}/env/include ${gencode}"
  ];

  # everything host-specific the wrapper needs; lib/agent.py is the same on every host
  conf = pkgs.writeText "gensokyo-agent.json" (builtins.toJSON {
    podman = "${pkgs.podman}/bin/podman";
    defaultCmd = "claude --dangerously-skip-permissions";
    inherit rootfs runArgs token home;
  });

  wrapper = pkgs.writers.writePython3Bin "gensokyo-agent" { flakeIgnore = [ "E501" ]; }
    (builtins.replaceStrings [ "@conf@" ] [ "${conf}" ] (builtins.readFile ./agent.py));
in
{
  options.gensokyo-agent = {
    enable = lib.mkEnableOption "the gensokyo-agent sandbox";
    user = lib.mkOption {
      type = lib.types.str;
      description = "Host user who drives the sandbox and may act as claude.";
    };
    uid = lib.mkOption { type = lib.types.int; default = 4738; };
    gid = lib.mkOption { type = lib.types.int; default = 384; };
  };

  config = lib.mkIf cfg.enable {
    users.groups.agent.gid = cfg.gid;
    users.users.claude = {
      isSystemUser = true;      # home defaults to /var/empty; nothing on the host
      uid = cfg.uid;
      group = "agent";
    };

    # user may act as claude inside their user namespace; linger keeps user@UID (and its
    # D-Bus) alive so rootless podman can reach systemd for cgroups from any session
    users.users.${cfg.user} = {
      linger = true;
      autoSubUidGidRange = true;
      subUidRanges = [ { startUid = cfg.uid; count = 1; } ];
      subGidRanges = [ { startGid = cfg.gid; count = 1; } { startGid = config.ids.gids.kvm; count = 1; } ];
    };

    boot.kernelModules = lib.optional cudaSupport "nvidia-uvm";
    virtualisation.podman.enable = true;
    environment.systemPackages = [ wrapper ];
    environment.etc."gensokyo-agent".source = hostDir;
  };
}
