# checks.<system>.agent-sandbox: the nix flavor of gensokyo-agent for real, in
# a VM: rootless podman, the uid map, a workspace built and run, and a sandbox
# inside the sandbox.
{ self, hostPkgs }:
let
  hostSystem = hostPkgs.stdenv.hostPlatform.system;
  # a project's flake with a closure for --closure. the VM has no network:
  # it builds what is built here already, from the same nixpkgs
  fakeClosure = pkgs: import ../lib/agent-closure.nix pkgs {
    packages = [ (pkgs.writeShellScriptBin "fake-mcp" "echo fake") ];
    mcpServers.fake.command = "fake-mcp";
  };
  agentFlake = hostPkgs.runCommand "agent-flake" { } ''
    mkdir $out
    cp ${../lib/agent-closure.nix} $out/agent-closure.nix
    cat > $out/flake.nix <<'EOF'
    {
      inputs.nixpkgs.url = "path:${hostPkgs.path}";
      outputs = { nixpkgs, ... }: let pkgs = nixpkgs.legacyPackages.${hostSystem}; in {
        agentClosures.${hostSystem}.fake = import ./agent-closure.nix pkgs {
          packages = [ (pkgs.writeShellScriptBin "fake-mcp" "echo fake") ];
          mcpServers.fake.command = "fake-mcp";
        };
      };
    }
    EOF
  '';
in
{
  name = "agent-sandbox";
  node.pkgsReadOnly = false;
  nodes.machine = { config, lib, pkgs, ... }: {
    imports = [ ../lib/ci.nix self.nixosModules.agent ];
    environment.systemPackages = [ pkgs.gitMinimal ];
    gensokyo.ci = true;
    gensokyo-agent = { enable = true; user = "alice"; };
    time.timeZone = "Asia/Tokyo";
    users.users.alice = { isNormalUser = true; uid = 1000; extraGroups = [ "gadget" ]; };
    users.groups.gadget = { };   # of a device only its group may write, for -d
    hardware.graphics.enable = true;   # /run/opengl-driver, which --legacy binds
    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 4096;
    virtualisation.additionalPaths = [ hostPkgs.path (fakeClosure hostPkgs) ];
    system.stateVersion = lib.mkDefault config.system.nixos.release;
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")
    machine.succeed("test -e /dev/kvm || mknod -m 666 /dev/kvm c 10 232")
    machine.succeed("install -d -o alice /home/alice/w")

    def agent(args):
        return ("sudo -u alice env HOME=/home/alice XDG_RUNTIME_DIR=/run/user/1000"
                " DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
                f" sh -c 'cd /home/alice/w && gensokyo-agent {args}' 2>&1")

    # what claude's own sandbox asks of the kernel: namespaces and a fresh /proc
    nested = "bwrap --ro-bind / / --dev /dev --unshare-all --proc /proc sh -c \"echo nested \\$\\$\""

    with subtest("the sandbox on the current directory"):
        out = machine.succeed(agent("--legacy sh -c \"id -u; touch \\$HOME/mine; pwd\""))
        assert "4738" in out and "/home/alice/w" in out, out
        # the clock is in the host's zone, and any other can be asked for
        out = machine.succeed(agent("--legacy sh -c \"readlink -f /etc/localtime; date +%Z; TZ=Europe/Berlin date +%Z\""))
        assert "/zoneinfo/Asia/Tokyo\nJST\nCET" in out.replace("\r", ""), out
        assert "nested 2" in machine.succeed(agent("--legacy " + nested))

    with subtest("a workspace is the agent's own"):
        out = machine.succeed(agent(
            "--name ws1 --cp /etc/hostname:notes/host -- sh -c"
            " \"id -u; cat notes/host; touch notes/mine \\$HOME/mine; git config user.name; pwd; date +%Z\""))
        assert "4738\nmachine\nClaude\n/var/tmp/gensokyo-agent/ws1\nJST" in out.replace("\r", ""), out
        assert "nested 2" in machine.succeed(agent("--name ws2 -- " + nested))

    with subtest("and it comes back after it stopped"):
        podman = "sudo -u alice env XDG_RUNTIME_DIR=/run/user/1000 podman"
        machine.succeed(f"{podman} start -a ws1")
        machine.succeed(f"{podman} rm ws1 ws2")

    with subtest("a workspace carries on from another: its claude home, at its path"):
        machine.succeed(agent(
            "--name fr1 -- sh -c \"mkdir -p \\$HOME/.claude/projects/p && echo said > \\$HOME/.claude/projects/p/s.jsonl\""))
        out = machine.succeed(agent(
            "--name fr2 --from fr1 -- sh -c"
            " \"cat \\$HOME/.claude/projects/p/s.jsonl; pwd; test -w \\$HOME/.claude/projects/p/s.jsonl && echo mine\""))
        assert "said\n/var/tmp/gensokyo-agent/fr1\nmine" in out.replace("\r", ""), out
        machine.succeed(f"{podman} rm fr1 fr2")

    with subtest("and under its own name replaces it, files and all"):
        machine.succeed(agent(
            "--name fr3 -- sh -c \"echo kept > mine; mkdir -p \\$HOME/.claude && echo said > \\$HOME/.claude/s\""))
        out = machine.succeed(agent(
            "--from fr3 -- sh -c \"cat mine \\$HOME/.claude/s; grep -c workspace.fr3 AGENTS.md; test -w mine && echo mine\""))
        assert "kept\nsaid\n1\nmine" in out.replace("\r", ""), out
        names = machine.succeed(podman + " ps -a --format {{.Names}}").split()
        assert names.count("fr3") == 1 and "fr3.replaced" not in names, names
        machine.succeed(f"{podman} rm fr3")

    with subtest("a device the owner may use, the agent may"):
        machine.succeed("mknod -m 660 /dev/gadget c 1 3 && chgrp gadget /dev/gadget")
        out = machine.succeed(agent(
            "--name dev1 -d /dev/gadget --rm -- sh -c \"echo x > /dev/gadget && echo wrote; test -w /dev/kvm && echo kvm\""))
        assert "wrote\nkvm" in out.replace("\r", ""), out

    with subtest("a closure from a flake, built before the workspace"):
        machine.succeed("cp -r ${agentFlake} /home/alice/proj && chmod -R u+w /home/alice/proj && chown -R alice /home/alice/proj")
        out = machine.succeed(agent(
            "--name cl1 --closure /home/alice/proj#fake -- sh -c"
            " \"fake-mcp; cat /.gensokyo-agent/closure/share/gensokyo-agent/mcp.json; grep -q built.by.the.owner AGENTS.md && echo noted\""))
        assert "fake\n{\"mcpServers\":{\"fake\":{\"command\":\"fake-mcp\"}}}noted" in out.replace("\r", ""), out
        # rooted for as long as the workspace is there
        root = "/home/alice/.local/state/gensokyo-agent/cl1/closure"
        machine.succeed(f"test $(readlink {root}) = ${fakeClosure hostPkgs}")
        machine.succeed(f"nix-store --gc --print-roots | grep -F {root}")
        # and one carried on from brings it along, rooted still
        out = machine.succeed(agent("--from cl1 -- sh -c \"fake-mcp; grep -q cl1..had AGENTS.md && echo noted\""))
        assert "fake\nnoted" in out.replace("\r", ""), out
        machine.succeed(f"test $(readlink {root}) = ${fakeClosure hostPkgs}")
        # without --closure, the module's own, which has no servers
        out = machine.succeed(agent("--name cl2 -- cat /.gensokyo-agent/closure/share/gensokyo-agent/mcp.json"))
        assert '{"mcpServers":{}}' in out, out
        machine.succeed(f"{podman} rm cl1 cl2")

    with subtest("a fetch wakes a stopped workspace, and leaves it stopped"):
        def alice(cmd):
            return ("sudo -u alice env HOME=/home/alice XDG_RUNTIME_DIR=/run/user/1000"
                    f" sh -c 'cd /home/alice/w && {cmd}' 2>&1")
        machine.succeed(alice("git init -q -b master . && git -c user.name=a -c user.email=a@b commit -q --allow-empty -m base"))
        # the second start (the fetch's) only waits to be asked
        machine.succeed(agent(
            "--name ws3 --git .:: -- sh -c"
            " \"test -e \\$HOME/done && exec sleep 600; touch \\$HOME/done; git -C src/w commit -q --allow-empty -m agent\""))
        running = podman + " container inspect -f {{.State.Running}} ws3"
        assert "false" in machine.succeed(running)
        machine.succeed(alice("git fetch ws3"))
        assert "agent" in machine.succeed(alice("git log -1 --format=%s ws3/ws3"))
        assert "false" in machine.succeed(running)
        machine.succeed(f"{podman} rm ws3")
  '';
}
