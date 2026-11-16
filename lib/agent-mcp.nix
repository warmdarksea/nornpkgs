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
  # The server speaks to `lake serve` and to nothing else, and takes a
  # directory only with a lakefile and a lean-toolchain in it. A project
  # that is built by nix needs neither in git: as the server starts, what
  # is missing is put in the checkout from the store and named in the
  # checkout's .git/info/exclude, so git does not see it. Lake is the way
  # the language server finds a file's imports, then, and builds what they
  # need under .lake/; it is not what builds the project.
  #
  # projects: directories (from the workspace: "src/NAME/core") that are not
  # Lake projects, each given a lakefile.toml and an empty lake-manifest.json
  # there. `name` is the package's, `libs` its libraries, each with the
  # globs of its modules ("Foo.+": all under Foo/; "Foo.*": Foo.lean too):
  #
  #   projects."src/my-project".libs.Foo = [ "Foo.*" ];
  #
  # A file of that name which is not a link of ours is left alone. A
  # directory with a lakefile of its own (a template's) needs no entry.
  #
  # leanDeps: nix's Lean libraries (leanPackages.mathlib), as buildLakePackage
  # takes them. A lakefile requires them (the one written here does), and
  # every project's .lake/package-overrides.json says where they are, for
  # `lake serve` and the agent's `lake build` to find them built and fetch
  # nothing. lean-toolchain names leanPackages.lean4, in every project that
  # has none.
  #
  # Projects are looked for one and two levels into src/, where
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
      projects ? { },
      disabledTools ? [
        "lean_hammer_premise"
        "lean_state_search"
      ],
    }:
    let
      lakeName = dep: dep.lakePackageName or dep.pname;
      allLeanDeps = lib.unique (lib.concatMap (dep: [ dep ] ++ (dep.allLeanDeps or [ ])) leanDeps);
      overrides = pkgs.writeText "lake-overrides.json" (
        builtins.toJSON {
          schemaVersion = "1.2.0";
          packages = map (dep: {
            type = "path";
            name = lakeName dep;
            inherited = false;
            dir = "${dep}";
          }) allLeanDeps;
        }
      );
      toolchain = pkgs.writeText "lean-toolchain" "leanprover/lean4:v${leanPackages.lean4.version}\n";
      manifest = pkgs.writeText "lake-manifest.json" (
        builtins.toJSON {
          version = "1.1.0";
          packagesDir = ".lake/packages";
          packages = [ ];
        }
      );
      lakefile =
        dir:
        {
          name ? baseNameOf dir,
          libs,
        }:
        (pkgs.formats.toml { }).generate "lakefile.toml" (
          {
            inherit name;
            defaultTargets = lib.attrNames libs;
            lean_lib = lib.mapAttrsToList (lib: globs: {
              name = lib;
              inherit globs;
            }) libs;
          }
          // lib.optionalAttrs (leanDeps != [ ]) {
            # never fetched: package-overrides.json has every one of them
            require = map (dep: {
              name = lakeName dep;
              git = "https://nix.invalid/${lakeName dep}";
              rev = "nix";
            }) leanDeps;
          }
        );
      command = pkgs.writeShellScript "lean-lsp-mcp-in-workspace" ''
        # put FILE of the store in DIR as NAME, unless DIR has its own
        put() {
          if [ -L "$1/$2" ] || [ ! -e "$1/$2" ]; then
            ln -sfn "$3" "$1/$2" && unseen "$1" "$2"
          fi
        }
        # keep NAME in DIR out of git's sight, without a word in .gitignore
        unseen() {
          local ex pre
          ex=$(git -C "$1" rev-parse --git-path info/exclude 2>/dev/null) || return 0
          pre=$(git -C "$1" rev-parse --show-prefix)
          case $ex in /*) ;; *) ex=$1/$ex ;; esac
          mkdir -p "''${ex%/*}"
          grep -qxF "/$pre$2" "$ex" 2>/dev/null || echo "/$pre$2" >> "$ex"
        }
        ${lib.concatStrings (
          lib.mapAttrsToList (dir: project: ''
            if [ -d "$PWD"/${lib.escapeShellArg dir} ]; then
              put "$PWD"/${lib.escapeShellArg dir} lakefile.toml ${lakefile dir project}
              put "$PWD"/${lib.escapeShellArg dir} lake-manifest.json ${manifest}
            fi
          '') projects
        )}
        found=
        n=0
        for d in "$PWD"/src/*/ "$PWD"/src/*/*/; do
          d=''${d%/}
          [ -f "$d/lakefile.lean" ] || [ -f "$d/lakefile.toml" ] || continue
          put "$d" lean-toolchain ${toolchain}
          found=$d
          n=$((n + 1))
          ${lib.optionalString (allLeanDeps != [ ]) ''
            mkdir -p "$d/.lake" && ln -sfn ${overrides} "$d/.lake/package-overrides.json"
          ''}
          unseen "$d" .lake
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
