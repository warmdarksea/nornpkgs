# MCP servers for theorem proving, for an agent closure (lib/agent-closure.nix).
# Each is { packages, server }: what the agent's own shell wants beside the
# server, and the server as mcpServers has it. With the caller's pkgs: the
# prover and its libraries are the project's.
#
#   lean = nornpkgs.lib.mkLeanMcp { inherit pkgs; leanDeps = [ pkgs.leanPackages.mathlib ]; };
#   rocq = nornpkgs.lib.mkRocqMcp { inherit pkgs; };
#   agentClosures.${system}.default = nornpkgs.lib.mkAgentClosure {
#     inherit pkgs;
#     packages = lean.packages ++ rocq.packages;
#     mcpServers.lean = lean.server;
#     mcpServers.rocq = rocq.server;
#   };
#
# Both were read for anything they should not do (2026-11-16: lean-lsp-mcp
# 0.31.0, rocq-mcp 5251f5c, pytanque 0.2.2). rocq-mcp is pinned in
# pkgs/rocq-mcp; lean-lsp-mcp is nixpkgs', and moves with it.
pkgs:
let
  inherit (pkgs) lib;
in
{
  # lean-lsp-mcp: goals, diagnostics, tactics tried without editing, search.
  #
  # leanDeps: nix's Lean libraries (leanPackages.mathlib), as buildLakePackage
  # takes them. A Lake project requires them in its lakefile and has a
  # lake-manifest.json without them; the server, as it starts, names them in
  # the project's .lake/package-overrides.json, for `lake serve` and the
  # agent's `lake build` to find them built and not fetch them.
  #
  # A project is a directory with lean-toolchain and a lakefile (the server
  # takes no other), looked for one and two levels into src/, where
  # gensokyo-agent --git puts a checkout. One project there is the server's
  # from the start; otherwise it takes the project of the file it is asked
  # about.
  #
  # disabledTools: the two that send the goal under the cursor to somebody
  # else's server: lean_hammer_premise (leanpremise.net, over plain http)
  # and, in the versions that have it, lean_state_search (premise-search.com).
  # The other searches (lean_leansearch, lean_loogle, lean_leanfinder) send
  # what the agent types, over https, to leansearch.net, loogle.lean-lang.org
  # and a leanfinder endpoint. A name the server does not have is a line in
  # its log.
  mkLeanMcp =
    {
      leanPackages ? pkgs.leanPackages,
      leanDeps ? [ ],
      disabledTools ? [
        "lean_hammer_premise"
        "lean_state_search"
      ],
    }:
    let
      allLeanDeps = lib.unique (lib.concatMap (dep: [ dep ] ++ (dep.allLeanDeps or [ ])) leanDeps);
      overrides = pkgs.writeText "lake-overrides.json" (
        builtins.toJSON {
          schemaVersion = "1.2.0";
          packages = map (dep: {
            type = "path";
            name = dep.lakePackageName or dep.pname;
            inherited = false;
            dir = "${dep}";
          }) allLeanDeps;
        }
      );
      command = pkgs.writeShellScript "lean-lsp-mcp-in-workspace" ''
        found=
        n=0
        for d in "$PWD"/src/*/ "$PWD"/src/*/*/; do
          [ -f "$d/lean-toolchain" ] || continue
          [ -f "$d/lakefile.lean" ] || [ -f "$d/lakefile.toml" ] || continue
          found=''${d%/}
          n=$((n + 1))
          ${lib.optionalString (allLeanDeps != [ ]) ''
            mkdir -p "$d/.lake" && ln -sfn ${overrides} "$d/.lake/package-overrides.json"
          ''}
        done
        if [ -z "''${LEAN_PROJECT_PATH-}" ] && [ $n = 1 ]; then
          export LEAN_PROJECT_PATH=$found
        fi
        export PATH=${lib.makeBinPath tools}:$PATH
        exec ${lib.getExe pkgs.lean-lsp-mcp} "$@"
      '';
      # lean and lake; rg for lean_local_search; cc for Lake to link an
      # executable with (nix's Lean brings none)
      tools = [
        leanPackages.lean4
        pkgs.ripgrep
        pkgs.stdenv.cc
      ];
    in
    {
      packages = tools;
      server = {
        command = "${command}";
      }
      // lib.optionalAttrs (disabledTools != [ ]) {
        env.LEAN_MCP_DISABLED_TOOLS = lib.concatStringsSep "," disabledTools;
      };
      # the libraries' oleans, for a `lean` that is run without Lake
      leanPath = lib.concatMapStringsSep ":" (p: "${p}/.lake/build/lib/lean") allLeanDeps;
      inherit allLeanDeps;
    };

  # rocq-mcp (pkgs/rocq-mcp): compile, verify, query, step through a proof
  # with pet. Its arguments are the package's: rocqPackages, rocq, rocqLibs.
  #
  # No ROCQ_WORKSPACE: a file's project is found from its _RocqProject,
  # _CoqProject or dune-project, and what is compiled from a string is written
  # (and removed) in the workspace, outside the checkouts.
  mkRocqMcp =
    args:
    let
      rocq-mcp = pkgs.callPackage ../pkgs/rocq-mcp args;
    in
    {
      packages = [ rocq-mcp.toolchain ];
      server.command = lib.getExe rocq-mcp;
      inherit rocq-mcp;
    };
}
