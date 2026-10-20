{
  description = "python hello world";

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
      python = pkgs.python3;

      # Exactly what the wheel is built from, and nothing else. `src = ./.`
      # would also copy in the nix out-links make leaves in build/ -- symlinks
      # to the *previous* output, which change this build's source hash every
      # time -- along with state/, __pycache__ and .pytest_cache.
      src = fs.toSource {
        root = ./.;
        fileset = fs.unions [
          ./pyproject.toml
          ./conftest.py
          (fs.fileFilter (f: f.hasExt "py") ./py_hello)
          (fs.fileFilter (f: f.hasExt "py") ./tests)
        ];
      };

      py-hello = python.pkgs.buildPythonApplication {
        pname = "py-hello";
        version = "0.1.0";
        pyproject = true;
        inherit src;
        build-system = [ python.pkgs.hatchling ];
        meta.mainProgram = "py-hello";
      };

      # Runs under rootless podman: a notebook cell is arbitrary code
      # execution by design, so the thing evaluating it does not get the
      # host. This project is the only writable mount.
      jupyter = nornpkgs.lib.mkJupyter {
        inherit pkgs;
        name = "py-hello";
        kernels.python = {
          displayName = "Python 3 (py-hello)";
          # the project itself, so a cell can `from py_hello import main`
          packages = ps: [ py-hello ];
        };
      };
    in
    {
      packages.${system} = {
        inherit py-hello jupyter;
        default = py-hello;
      };

      devShells.${system} = {
        default = pkgs.mkShell {
          packages = [
            (python.withPackages (ps: [ ps.pytest ]))
          ];
        };

        # `nix develop .#jupyter` -- the server wrapper and podman, without
        # any of that weight in the default shell.
        jupyter = pkgs.mkShell { packages = [ jupyter ]; };
      };
    };
}
