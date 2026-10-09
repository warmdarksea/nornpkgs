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

      lean4-hello = pkgs.leanPackages.buildLakePackage {
        pname = "lean4-hello";
        version = "0.1.0";
        src = ./.;
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
        packages = [ pkgs.leanPackages.lean4 ];
      };
    };
}
