{
  description = "python + torch hello: matrix multiply on the GPU";

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

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          cudaSupport = true;
          # RTX 3090 (sm_86) and RTX 4070 Ti Laptop (sm_89).
          cudaCapabilities = [
            "8.6"
            "8.9"
          ];
          cudaForwardCompat = false; # skip the extra PTX for future archs
        };
        overlays = [
          (final: prev: {
            # torch-bin 2.12 requires CUDA >= 13; 13.2 also matches the 595.xx driver.
            cudaPackages = final.cudaPackages_13;
            # The torch wheel pins setuptools<82 but nixpkgs ships 83; harmless.
            python3 = prev.python3.override {
              packageOverrides = pyfinal: pyprev: {
                torch-bin = pyprev.torch-bin.overridePythonAttrs (old: {
                  pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "setuptools" ];
                });
              };
            };
            python3Packages = final.python3.pkgs;
          })
        ];
      };

      python = pkgs.python3;

      py-hellotorch = python.pkgs.buildPythonApplication {
        pname = "py-hellotorch";
        version = "0.1.0";
        pyproject = true;
        src = ./.;
        build-system = [ python.pkgs.hatchling ];
        dependencies = [ python.pkgs.torch-bin ];
        meta.mainProgram = "py-hellotorch";
      };

      # Runs under rootless podman: a notebook cell is arbitrary code
      # execution by design, so the thing evaluating it does not get the
      # host. cuda binds the gpu devices and the host driver into the
      # sandbox; torch needs no LD_LIBRARY_PATH of its own, since nixpkgs
      # stamps the driver path into its RUNPATH.
      jupyter = nornpkgs.lib.mkJupyter {
        inherit pkgs;
        name = "py-hellotorch";
        kernels.python = {
          displayName = "Python 3 (torch)";
          packages = ps: [
            ps.torch-bin
            ps.numpy
            py-hellotorch # so a cell can `from py_hellotorch import main`
          ];
          cuda = true;
        };
        port = 8889;
      };
    in
    {
      packages.${system} = {
        inherit py-hellotorch jupyter;
        default = py-hellotorch;
      };

      devShells.${system} = {
        default = pkgs.mkShell {
          packages = [
            (python.withPackages (ps: [
              ps.torch-bin
              ps.numpy
              ps.pytest
            ]))
          ];
        };

        # `nix develop .#jupyter` -- the server wrapper and podman, without
        # any of that weight in the default shell.
        jupyter = pkgs.mkShell { packages = [ jupyter ]; };
      };
    };
}
