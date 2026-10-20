{
  description = "lean 4 proofs with mathlib; building type-checks them";

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
      # in build/, a symlink to the *previous* output: that changes this
      # build's source hash on every build, and since this is a library (the
      # whole package tree is installed) it also plants a dangling store
      # symlink in $out, which fixup's noBrokenSymlinks check rejects.
      src = fs.toSource {
        root = ./.;
        fileset = fs.difference (fs.unions [
          ./lakefile.lean
          ./lake-manifest.json
          (fs.fileFilter (f: f.hasExt "lean") ./.)
        ]) (fs.unions (map fs.maybeMissing [ ./build ./.lake ]));
      };

      # A library of proofs -- building it type-checks them -- plus the small
      # Mathlib-free executable `make run` runs. isLibrary (the default)
      # installs the olean tree *and* symlinks any built binary into $out/bin.
      lean4-hellomath = leanPackages.buildLakePackage {
        pname = "lean4-hellomath";
        version = "0.1.0";
        inherit src;
        leanDeps = [ leanPackages.mathlib ];
        meta.mainProgram = "lean4-hellomath";
      };
    in
    {
      packages.${system} = {
        inherit lean4-hellomath;
        default = lean4-hellomath;
      };

      devShells.${system}.default = pkgs.mkShell {
        # lake is part of lean4; no elan
        packages = [ leanPackages.lean4 ];
      };
    };
}
