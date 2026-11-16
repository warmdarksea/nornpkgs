{
  description = "lean 4 hello world";

  # No flake.lock in the template: this resolves through the system nix
  # registry pin (and nornpkgs, below, to its newest), and nix writes a lock
  # beside the flake the first time it builds.
  inputs.nixpkgs.url = "nixpkgs";

  # The agent's harness: what gensokyo-agent --closure gives an agent here.
  inputs.nornpkgs.url = "github:warmdarksea/nornpkgs";
  inputs.nornpkgs.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { self, nixpkgs, nornpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib leanPackages;
      fs = lib.fileset;

      # Exactly what lake needs, and nothing else. `src = ./.` would also copy
      # in what make and lake leave behind -- in particular the nix out-link
      # in build/, a symlink to the *previous* output, which changes this
      # build's source hash on every build and so never stops rebuilding.
      src = fs.toSource {
        root = ./.;
        fileset = fs.difference (fs.unions [
          ./lakefile.lean
          ./lake-manifest.json
          (fs.fileFilter (f: f.hasExt "lean") ./.)
        ]) (fs.unions (map fs.maybeMissing [ ./build ./.lake ]));
      };

      lean4-hello = leanPackages.buildLakePackage {
        pname = "lean4-hello";
        version = "0.1.0";
        inherit src;
        isLibrary = false;
        meta.mainProgram = "lean4-hello";
      };

      # lean-lsp-mcp, on this Lean. The lean-toolchain it wants beside the
      # lakefile is put there as it starts, out of git's sight, naming this Lean.
      lean = nornpkgs.lib.mkLeanMcp { inherit pkgs; };
    in
    {
      packages.${system} = {
        inherit lean4-hello;
        default = lean4-hello;
      };

      devShells.${system}.default = pkgs.mkShell {
        # lake is part of lean4; no elan
        packages = [ leanPackages.lean4 ];
      };

      # gensokyo-agent --closure . --git .::
      # an agent with lean and lake, and the Lean MCP server on this project
      agentClosures.${system}.default = nornpkgs.lib.mkAgentClosure {
        inherit pkgs;
        inherit (lean) packages;
        mcpServers.lean = lean.server;
      };
    };
}
