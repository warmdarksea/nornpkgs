{
  description = "python hello world";

  # Pinned by the committed flake.lock; `nix flake update` re-resolves it
  # through the machine's nix registry.
  inputs.nixpkgs.url = "nixpkgs";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      python = pkgs.python3;
    in
    {
      packages.${system}.default = python.pkgs.buildPythonApplication {
        pname = "py-hello";
        version = "0.1.0";
        pyproject = true;
        src = ./.;
        build-system = [ python.pkgs.hatchling ];
        meta.mainProgram = "py-hello";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          (python.withPackages (ps: [ ps.pytest ]))
        ];
      };
    };
}
