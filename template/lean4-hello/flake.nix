{
  description = "lean 4 hello world";

  # Resolves through the system nix registry pin.
  inputs.nixpkgs.url = "nixpkgs";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = pkgs.leanPackages.buildLakePackage {
        pname = "lean4-hello";
        version = "0.1.0";
        src = ./.;
        isLibrary = false;
        meta.mainProgram = "lean4-hello";
      };

      devShells.${system}.default = pkgs.mkShell {
        # lake is part of lean4; no elan
        packages = [ pkgs.leanPackages.lean4 ];
      };
    };
}
