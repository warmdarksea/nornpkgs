# gensokyo-agent — rootless podman sandbox for coding agents (claude, codex, opencode, agy).
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
# agy (antigravity-cli) gets not that but its own: its google login, signed in
# once in a workspace (the URL it prints, the code pasted back) and saved,
#   podman cp NAME:/home/agent/.gemini/antigravity-cli/antigravity-oauth-token - | tar -xO | podman secret create agy-oauth-token -
# or, failing that, an API key of aistudio.google.com (billed by its project):
#   printf %s "$key" | podman secret create gemini-api-key -
#   gensokyo-agent --git .:: --harness antigravity
#
# Usage (gensokyo-agent --help has the flags and examples):
#   gensokyo-agent --git .:master: --prompt "fix the build"
#                                         a workspace: a clone on master (and whatever --cp,
#                                         --ro, --rw add), built into an image, in a container that
#                                         stays until podman rm. the checkout gets a remote to fetch
#                                         its commits from. -c NAME puts it all on another host
#                                         (podman system connection add)
#   gensokyo-agent --closure .#NAME --git .::
#                                         with the packages and MCP servers of this flake's
#                                         agentClosures.<system>.NAME (lib/agent-closure.nix)
#   gensokyo-agent --from OLD --closure .#NAME
#                                         OLD again (its claude home, at its path, and its files),
#                                         say for another closure: it is replaced under its name
#   gensokyo-agent -c HOST --from CONN/OLD --git-add-remote .
#                                         a copy of OLD on the host of CONN, closure and all, on
#                                         HOST; this checkout gets the remote OLD to it, if it has
#                                         none of that name already
#   gensokyo-agent --harness codex        another agent in it, gpt there
#   gensokyo-agent --legacy               claude in a throwaway sandbox on the current directory
#   gensokyo-agent --legacy codex         any command there
#   AGENT_CMD="opencode" gensokyo-agent   change the default
#
# MCP servers: those of the closure, declared by the project, which packages them; and the
# workspace's .mcp.json, which the agent may edit with the owner's approval. none in the module
{ config, pkgs, lib, ... }:
let
  cfg = config.gensokyo-agent;
  g = config.users.groups.agent;
  cudaSupport = pkgs.config.cudaSupport or false;
  cuda = pkgs.cudaPackages;
  gencode = lib.concatStringsSep " " cuda.flags.gencode;
  gid = toString g.gid;
  kvm = toString config.ids.gids.kvm;
  home = "/home/agent";             # container-only, and gone with the container

  # who the agent is in the sandbox: one user per maker of models, claude's
  # whichever claude it is, and agent for any other. uid gensokyo-agent.uid
  # and on, in this order, all of the group agent; what it commits as
  agentUsers = lib.imap0 (i: u: u // { uid = cfg.uid + i; }) [
    { name = "claude"; git = { name = "Claude"; email = "claude@anthropic.com"; }; }
    { name = "gpt"; git = { name = "GPT"; email = "codex@openai.com"; }; }
    { name = "gemini"; git = { name = "Gemini"; email = "gemini@google.com"; }; }
    { name = "deepseek"; git = { name = "DeepSeek"; email = "deepseek@deepseek.com"; }; }
    { name = "qwen"; git = { name = "Qwen"; email = "qwen@alibabacloud.com"; }; }
    { name = "kimi"; git = { name = "Kimi"; email = "kimi@moonshot.cn"; }; }
    { name = "inkling"; git = { name = "Inkling"; email = "inkling@thinkingmachines.ai"; }; }
    { name = "agent"; git = { name = "Agent"; email = "agent@gensokyo.internal"; }; }
  ];
  # gensokyo-agent --harness NAME: the command, and the user of its own
  # models when --model names none
  harnesses = {
    # the env scrub puts claude back in its default permission mode; the tools are allowed by name,
    # and anything else by a hook the wrapper puts in the sandbox's settings
    claude-code = { cmd = "claude --dangerously-skip-permissions --allowedTools Edit,MultiEdit,Write,NotebookEdit,Bash,WebSearch,WebFetch"; user = "claude"; };
    antigravity = { cmd = "agy --dangerously-skip-permissions"; user = "gemini"; };
    # the container is the sandbox
    codex = { cmd = "codex --dangerously-bypass-approvals-and-sandbox"; user = "gpt"; };
  };
  # --model's user: the first whose pattern (python's re, ignoring case) it matches
  modelUsers = [
    [ "claude|opus|sonnet|haiku|fable" "claude" ]
    [ "gpt|codex|^o[0-9]" "gpt" ]
    [ "gemini" "gemini" ]
    [ "deepseek" "deepseek" ]
    [ "qwen" "qwen" ]
    [ "kimi|moonshot" "kimi" ]
    [ "inkling" "inkling" ]
  ];

  env = pkgs.buildEnv {
    name = "gensokyo-agent-env";
    paths = with pkgs; [
      nix gitMinimal bashInteractive
      coreutils findutils gnused gnugrep gawk diffutils which file tree less
      curl wget netcat nmap
      procps util-linux jq ripgrep fd
      bubblewrap socat   # what claude runs its commands in, see CLAUDE_CODE_SUBPROCESS_ENV_SCRUB
    ] ++ lib.optionals (!config.gensokyo.ci) [
      claude-code codex opencode
      antigravity-cli   # agy, google's. unfree: sys/hell allows it by name
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
  # where a sandbox has its closure (lib/agent-closure.nix): the default one
  # of ${hostPath}, or one built from a flake with --closure
  closurePath = "/.gensokyo-agent/closure";
  hostDir = pkgs.linkFarm "gensokyo-agent-host" ({
    inherit env;
    nixpkgs = pkgs.path;
    "ca-bundle.crt" = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    "nix.conf" = config.environment.etc."nix/nix.conf".source;
    "registry.json" = config.environment.etc."nix/registry.json".source;
    zoneinfo = "${pkgs.tzdata}/share/zoneinfo";
    # this host's zone; one set by hand (timedatectl, time.timeZone = null) is not followed
    localtime = "${pkgs.tzdata}/share/zoneinfo/${if config.time.timeZone == null then "UTC" else config.time.timeZone}";
    # the closure of a sandbox without --closure
    closure = import ./agent-closure.nix pkgs { name = "gensokyo-agent-closure"; };
  } // lib.optionalAttrs cudaSupport {
    cc = cuda.backendStdenv.cc;
  });

  nss = pkgs.dockerTools.fakeNss.override {
    extraPasswdLines = map (u: "${u.name}:x:${toString u.uid}:${gid}::${home}:/bin/sh") agentUsers;
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
    # lean's server, for one, does not start without /etc/localtime.
    # /etc/zoneinfo is where NixOS keeps the other zones
    ln -s ${hostPath}/localtime $out/etc/localtime
    ln -s ${hostPath}/zoneinfo $out/etc/zoneinfo
    # /etc/gitconfig, the user's name and address, is the wrapper's
  '';

  # the one secret every sandbox gets; from `claude setup-token`, never
  # ANTHROPIC_API_KEY, that bills API credits
  token = { secret = "claude-oauth-token"; target = "CLAUDE_CODE_OAUTH_TOKEN"; };
  # what the wrapper knows of each agent, by the name of its command:
  #   flags   how it takes --model and --effort (%s the value); an agent
  #           without them is refused either, and takes its own after --
  #   tokens  its own logins, in place of claude's (agy, scrubbing nothing,
  #           would hand claude's to every command it runs): the first there
  #           is a podman secret for, as the variable target, or copied to
  #           the file file of the home at the first start. without any agy
  #           starts logged out, and its google login (the URL it prints, the
  #           code pasted back) lasts in that file, there being no keyring:
  #           once per workspace, unless it is made the secret
  #   args    podman's, for it
  #   home    files of its home: an attrset as JSON, merged with a token's,
  #           text as it is
  #   mcp     where the closure's MCP servers go in its home, and in which of
  #           the formats lib/agent.py converts them to; claude is given them
  #           by flag
  agents = {
    claude.flags = { model = [ "--model" "%s" ]; effort = [ "--effort" "%s" ]; };
    agy = {
      flags = { model = [ "--model" "%s" ]; effort = [ "--effort" "%s" ]; };
      tokens = [
        # the google login of a workspace, a subscription's:
        #   podman cp NAME:/home/agent/.gemini/antigravity-cli/antigravity-oauth-token - | tar -xO | podman secret create agy-oauth-token -
        { secret = "agy-oauth-token"; file = ".gemini/antigravity-cli/antigravity-oauth-token"; }
        # an API key of aistudio.google.com, billed by its project
        {
          secret = "gemini-api-key";
          target = "GEMINI_API_KEY";
          # agy reads the key only with this in its settings, and will not start without the key then
          home.".gemini/antigravity-cli/settings.json" = { modelProvider = "gemini"; };
        }
      ];
      home.".gemini/antigravity-cli/settings.json" = { colorScheme = "solarized light"; };
      # its telemetry is a setting of the account, but where it goes is clearcut's,
      # signed in or not: nowhere
      args = [ "--add-host" "play.googleapis.com:127.0.0.1" ];
      missing = "agy starts logged out: sign in with the URL it prints, then save that login (lib/agent.nix says how); or an API key of aistudio.google.com";
      mcp = { path = ".gemini/config/mcp_config.json"; format = "agy"; };
    };
    codex = {
      flags = { model = [ "-m" "%s" ]; effort = [ "-c" "model_reasoning_effort=%s" ]; };
      home.".codex/config.toml" = ''
        [tui]
        theme = "solarized-light"

        [analytics]
        enabled = false

        [feedback]
        enabled = false

      '';
      # after the rest of its config, there being none else in the sandbox
      mcp = { path = ".codex/config.toml"; format = "codex"; };
    };
  };

  nixArgs = [
    # catatonit as pid 1. without it the agent itself is pid 1, and pid 1
    # in a pid namespace is the only process that can reap orphans -- so
    # anything the agent daemonises (a jupyter server, a dev server, any
    # nohup'd thing) is reparented to a process that never calls wait()
    # and stays a zombie for the life of the sandbox. zombies still answer
    # `kill -0`, which makes a pidfile look live long after the process
    # has gone. nixpkgs' podman points init_path at catatonit already.
    "--init"
    # the user's uid (the wrapper's to add, as it picks the user) and gid
    "--uidmap" "0:0:1"
    "--gidmap" "0:0:1" "--gidmap" "${gid}:@${gid}:1" "--gidmap" "${kvm}:@${kvm}:1"
    "--mount" "type=tmpfs,destination=/tmp,tmpfs-mode=1777,tmpfs-size=8g"
    # a sandbox inside this one (claude's, for the commands it runs) mounts its
    # own /proc, which the kernel refuses while parts of ours are masked
    "--security-opt" "unmask=ALL"
    "-v" "/nix:/nix:ro"
    "-v" "/nix/var/nix/daemon-socket/socket:/nix/var/nix/daemon-socket/socket"
    "-v" "${hostPath}:${hostPath}:ro"
    "-e" "HOME=${home}"
    "-e" "IS_SANDBOX=1"
    # no credential in the environment of what claude runs, which it then
    # runs in a sandbox of its own (bubblewrap, socat) and no longer unasked
    "-e" "CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1"
    # nor the connectors of the owner's claude.ai account (mail, drives and the like)
    "-e" "ENABLE_CLAUDEAI_MCP_SERVERS=0"
    # no telemetry, error reports or surveys of claude's (agy's is a setting
    # of the google account, /config there; codex's is in its config.toml)
    "-e" "DISABLE_TELEMETRY=1"
    "-e" "DISABLE_ERROR_REPORTING=1"
    "-e" "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1"
    # claude kills a command after 2 minutes unless it asked for longer, and
    # may ask for 10 at most; a host evaluation or a build takes more
    "-e" "BASH_DEFAULT_TIMEOUT_MS=600000"
    "-e" "BASH_MAX_TIMEOUT_MS=3600000"
    "-e" "PATH=${closurePath}/bin:${hostPath}/env/bin"
    "-e" "NIX_PATH=nixpkgs=${hostPath}/nixpkgs"
    "-e" "SSL_CERT_FILE=${hostPath}/ca-bundle.crt"
    # where glibc looks up the zone of a TZ; nixpkgs' has no zones of its own
    "-e" "TZDIR=${hostPath}/zoneinfo"
  ];
  vmArgs = [ "--group-add" kvm "--device" "/dev/kvm" ];
  glArgs = [
    "-v" "/run/opengl-driver:/run/opengl-driver:ro"
    "-e" "LD_LIBRARY_PATH=/run/opengl-driver/lib"
  ];
  cudaArgs = [
    "--device" "/dev/nvidiactl" "--device" "/dev/nvidia0"
    "--device" "/dev/nvidia-uvm" "--device" "/dev/nvidia-uvm-tools"
    "-e" "CUDA_PATH=${hostPath}/env"
    "-e" "NVCC_PREPEND_FLAGS=-ccbin ${hostPath}/cc/bin/g++ -I${hostPath}/env/include ${gencode}"
  ];

  # everything host-specific the wrapper needs; lib/agent.py is the same on every host
  conf = pkgs.writeText "gensokyo-agent.json" (builtins.toJSON {
    podman = "${pkgs.podman}/bin/podman";
    inherit harnesses modelUsers token agents;
    defaultHarness = "claude-code";
    users = lib.listToAttrs (map (u: lib.nameValuePair u.name { inherit (u) uid git; }) agentUsers);
    inherit gid;
    git = "${pkgs.gitMinimal}/bin/git";
    nix = "${config.nix.package}/bin/nix";
    system = pkgs.stdenv.hostPlatform.system;
    closure = { at = closurePath; default = "${hostPath}/closure"; };
    ssh = "${pkgs.openssh}/bin/ssh";
    # gensokyo-agent --legacy: the same sandbox on the current directory
    hereArgs = [ "--rm" "--log-driver" "none" "-v" "${hostPath}/closure:${closurePath}:ro" ]
      ++ nixArgs ++ vmArgs ++ glArgs ++ lib.optionals cudaSupport cudaArgs;
    # a workspace: an image of these files for / and the home, run with these arguments
    root = rootfs;
    inherit home;
    runArgs = nixArgs;
    # --gpu asks; whether the host has the devices is its business
    gpuArgs = glArgs ++ cudaArgs;
    # on unless --no-vm, for a host without kvm
    inherit vmArgs;
  });

  cli = pkgs.writers.writePython3Bin "gensokyo-agent" { flakeIgnore = [ "E501" ]; }
    (builtins.replaceStrings [ "@conf@" ] [ "${conf}" ] (builtins.readFile ./agent.py));
  wrapper = pkgs.runCommand "gensokyo-agent" { } ''
    mkdir -p $out/bin $out/share/bash-completion/completions
    ln -s ${cli}/bin/gensokyo-agent $out/bin/
    ln -s ${./agent-completion.bash} $out/share/bash-completion/completions/gensokyo-agent
  '';
in
{
  options.gensokyo-agent = {
    enable = lib.mkEnableOption "the gensokyo-agent sandbox";
    user = lib.mkOption {
      type = lib.types.str;
      description = "Host user who drives the sandbox and may act as its users.";
    };
    uid = lib.mkOption {
      type = lib.types.int;
      default = 4738;
      description = "The first of the sandbox's users, claude; the others follow.";
    };
    gid = lib.mkOption { type = lib.types.int; default = 384; };
  };

  config = lib.mkIf cfg.enable {
    users.groups.agent.gid = cfg.gid;
    # home defaults to /var/empty; nothing on the host
    users.users = lib.listToAttrs (map (u: lib.nameValuePair u.name {
      isSystemUser = true;
      inherit (u) uid;
      group = "agent";
    }) agentUsers) // {
      # user may act as each inside their user namespace; linger keeps user@UID (and its
      # D-Bus) alive so rootless podman can reach systemd for cgroups from any session
      ${cfg.user} = {
        linger = true;
        autoSubUidGidRange = true;
        subUidRanges = [ { startUid = cfg.uid; count = lib.length agentUsers; } ];
        subGidRanges = [ { startGid = cfg.gid; count = 1; } { startGid = config.ids.gids.kvm; count = 1; } ];
      };
    };

    boot.kernelModules = lib.optional cudaSupport "nvidia-uvm";
    virtualisation.podman.enable = true;
    environment.systemPackages = [ wrapper ];
    environment.etc."gensokyo-agent".source = hostDir;
  };
}
