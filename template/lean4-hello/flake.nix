{
  description = "lean 4 hello world";

  # Pinned by the committed flake.lock; `nix flake update` re-resolves it
  # through the machine's nix registry.
  inputs.nixpkgs.url = "nixpkgs";

  outputs =
    { self, nixpkgs }:
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
    };
}
