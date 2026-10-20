{
  description = "rust hello world";

  # Pinned by the committed flake.lock; `nix flake update` re-resolves it
  # through the machine's nix registry.
  inputs.nixpkgs.url = "nixpkgs";

  # The sandboxed jupyter server: kernels, the extension list and the podman
  # wrapper all live in nornpkgs lib/jupyter.nix. Not in the committed lock,
  # so the first build adds it. When hacking on the module itself:
  #   make start_jupyter NORNPKGS=path:/home/clownpiece/src/nornpkgs
  inputs.nornpkgs.url = "github:warmdarksea/nornpkgs";
  inputs.nornpkgs.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { self, nixpkgs, nornpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;
      fs = lib.fileset;

      # Exactly what cargo is given, and nothing else. `src = ./.` would also
      # copy in the nix out-links make leaves in build/ -- symlinks to the
      # *previous* output, which change this build's source hash every time --
      # along with state/ and cargo's own target/.
      src = fs.toSource {
        root = ./.;
        fileset = fs.unions [
          ./Cargo.toml
          ./Cargo.lock
          ./src
        ];
      };

      rust-hello = pkgs.rustPlatform.buildRustPackage {
        pname = "rust-hello";
        version = "0.1.0";
        inherit src;
        cargoLock.lockFile = ./Cargo.lock;
        meta.mainProgram = "rust-hello";
      };

      # Runs under rootless podman: a notebook cell is arbitrary code
      # execution by design, so the thing evaluating it does not get the
      # host. The evcxr kernel rebuilds a scratch crate per cell and resolves
      # `:dep` against crates.io, which is the main reason to want it boxed
      # in; its cargo dirs land under the project's state dir.
      #
      # jupyter-lsp ships no rust-analyzer spec, so the LSP features in the
      # default extension list cover python only here.
      jupyter = nornpkgs.lib.mkJupyter {
        inherit pkgs;
        name = "rust-hello";
        kernels.rust = { };
        port = 8890;
      };
    in
    {
      packages.${system} = {
        inherit rust-hello jupyter;
        default = rust-hello;
      };

      devShells.${system} = {
        default = pkgs.mkShell {
          packages = with pkgs; [
            rustc
            cargo
            clippy
            rustfmt
            rust-analyzer
          ];
        };

        # `nix develop .#jupyter` -- the server wrapper and podman, without
        # any of that weight in the default shell.
        jupyter = pkgs.mkShell { packages = [ jupyter ]; };
      };
    };
}
