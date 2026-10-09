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
      inherit (pkgs) leanPackages;

      # A library of proofs: building it type-checks them.
      lean4-hellomath = leanPackages.buildLakePackage {
        pname = "lean4-hellomath";
        version = "0.1.0";
        src = ./.;
        leanDeps = [ leanPackages.mathlib ];
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
