# gensokyo-agent — rootless podman sandbox for coding agents (claude, codex, opencode).
# Import on each host; everything is derived from that host's config.
#
# Per-host:
#   gensokyo-agent = { enable = true; user = "clownpiece"; };
#   nixpkgs.config = { cudaSupport = true; cudaCapabilities = [ "8.6" ]; };
#
# One-time, as the user (rootless secrets are per-user):
#   gensokyo-agent claude setup-token            # browser flow, prints a 1-year token
#   printf %s "$token" | podman secret create claude-oauth-token -
#   printf %s "$key"   | podman secret create openai-api-key -      # optional, for codex
# ...or skip secrets entirely and /login once; credentials persist in the home volume.
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
  cuda = pkgs.cudaPackages;
  gencode = lib.concatStringsSep " " cuda.flags.gencode;
  uid = toString u.uid;
  gid = toString g.gid;
  kvm = toString config.ids.gids.kvm;
  home = "/home/agent";             # container-only; lives in a named volume

  env = pkgs.buildEnv {
    name = "gensokyo-agent-env";
    paths = with pkgs; [
      nix gitMinimal bashInteractive
      coreutils findutils gnused gnugrep gawk diffutils which file tree less
      curl wget netcat nmap
      procps util-linux jq ripgrep fd
      claude-code codex opencode
      cuda.cudatoolkit
      config.hardware.nvidia.package.bin
    ];
  };

  nss = pkgs.dockerTools.fakeNss.override {
    extraPasswdLines = [ "claude:x:${uid}:${gid}::${home}:/bin/sh" ];
    extraGroupLines = [ "agent:x:${gid}:" ];
  };

  # real directories at the top level: podman populates /etc before /nix is mounted,
  # so nothing above the leaves may be a symlink into the store. /etc/nix on the host
  # is symlinks via /etc/static, so copy the resolved files from config instead of mounting.
  rootfs = pkgs.runCommand "gensokyo-agent-rootfs" { } ''
    mkdir -p $out/{etc/nix,bin,usr/bin,tmp} $out${home}
    cp -rL ${nss}/etc/. $out/etc/
    cp -L ${config.environment.etc."nix/nix.conf".source} $out/etc/nix/nix.conf
    cp -L ${config.environment.etc."nix/registry.json".source} $out/etc/nix/registry.json
    ln -s ${pkgs.dockerTools.binSh}/bin/sh $out/bin/sh
    ln -s ${pkgs.dockerTools.usrBinEnv}/usr/bin/env $out/usr/bin/env
  '';

  # podman secret name -> env var inside the sandbox; skipped if not created
  secrets = {
    claude-oauth-token = "CLAUDE_CODE_OAUTH_TOKEN";   # from `claude setup-token`; never ANTHROPIC_API_KEY, that bills API credits
    openai-api-key = "OPENAI_API_KEY";
  };

  wrapper = pkgs.writeShellApplication {
    name = "gensokyo-agent";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      : "''${DEBUG:=0}"
      : "''${AGENT_CMD:=claude --dangerously-skip-permissions}"

      # rootless podman can't write into a root-owned store path (unmapped uid, no
      # DAC override in the userns), so stage the skeleton somewhere we own
      base="''${XDG_RUNTIME_DIR:-/tmp}/gensokyo-agent"
      mkdir -p "$base"
      root=$(mktemp -d "$base/root.XXXXXX")
      trap 'podman unshare rm -rf "$root"' EXIT   # anything uid ${uid} left behind is only ours inside the userns
      cp -r ${rootfs}/. "$root/" && chmod -R u+w "$root" && chmod 755 "$root"   # mktemp gives 0700; / must be traversable by uid ${uid}

      args=(
        --rm --log-driver none
        --rootfs
        --uidmap 0:0:1 --uidmap ${uid}:@${uid}:1
        --gidmap 0:0:1 --gidmap ${gid}:@${gid}:1 --gidmap ${kvm}:@${kvm}:1
        --user ${uid}:${gid} --group-add ${kvm}
        --device /dev/kvm
        --device /dev/nvidiactl --device /dev/nvidia0
        --device /dev/nvidia-uvm --device /dev/nvidia-uvm-tools
        -v gensokyo-agent-home:${home}:U
        --mount "type=tmpfs,destination=/tmp,tmpfs-mode=1777,tmpfs-size=8g"
        -v /nix:/nix:ro
        -v /nix/var/nix/daemon-socket/socket:/nix/var/nix/daemon-socket/socket
        -v /run/opengl-driver:/run/opengl-driver:ro
        -v "$PWD:$PWD" -w "$PWD"
        -e HOME=${home}
        -e PATH=${env}/bin
        -e NIX_PATH=nixpkgs=${pkgs.path}
        -e SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
        -e LD_LIBRARY_PATH=/run/opengl-driver/lib
        -e CUDA_PATH=${env}
        -e NVCC_PREPEND_FLAGS="-ccbin ${cuda.backendStdenv.cc}/bin/g++ -I${env}/include ${gencode}"
      )
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: var: ''
        podman secret exists ${name} && args+=(--secret "${name},type=env,target=${var}")
      '') secrets)}
      [[ -t 0 ]] && args+=(-it)
      [[ $DEBUG == 1 ]] && { args+=(--log-level=debug); set -x; }

      if (($#)); then cmd=("$@"); else read -ra cmd <<< "$AGENT_CMD"; fi
      echo "gensokyo-agent: $PWD :: ''${cmd[*]}" >&2
      podman run "''${args[@]}" "$root" "''${cmd[@]}"
    '';
  };
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

    boot.kernelModules = [ "nvidia-uvm" ];
    virtualisation.podman.enable = true;
    environment.systemPackages = [ wrapper ];
  };
}
