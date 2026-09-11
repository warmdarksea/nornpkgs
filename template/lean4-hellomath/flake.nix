{
  description = "lean 4 proofs with mathlib; building type-checks them";

  # Resolves through the system nix registry pin.
  inputs.nixpkgs.url = "nixpkgs";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) leanPackages;
    in
    {
      # A library of proofs: building it type-checks them.
      packages.${system}.default = leanPackages.buildLakePackage {
        pname = "lean4-hellomath";
        version = "0.1.0";
        src = ./.;
        leanDeps = [ leanPackages.mathlib ];
      };

      devShells.${system}.default = pkgs.mkShell {
        # lake is part of lean4; no elan
        packages = [ leanPackages.lean4 ];
      };
    };
}
