{
  description = "rust hello world";

  # Pinned by the committed flake.lock; `nix flake update` re-resolves it
  # through the machine's nix registry.
  inputs.nixpkgs.url = "nixpkgs";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage {
        pname = "rust-hello";
        version = "0.1.0";
        src = ./.;
        cargoLock.lockFile = ./Cargo.lock;
        meta.mainProgram = "rust-hello";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          rustc
          cargo
          clippy
          rustfmt
          rust-analyzer
        ];
      };
    };
}
