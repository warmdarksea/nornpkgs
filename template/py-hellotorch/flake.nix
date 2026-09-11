{
  description = "python + torch hello: matrix multiply on the GPU";

  # Resolves through the system nix registry pin.
  inputs.nixpkgs.url = "nixpkgs";

  outputs =
    { self, nixpkgs }:
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
    in
    {
      packages.${system}.default = python.pkgs.buildPythonApplication {
        pname = "py-hellotorch";
        version = "0.1.0";
        pyproject = true;
        src = ./.;
        build-system = [ python.pkgs.hatchling ];
        dependencies = [ python.pkgs.torch-bin ];
        meta.mainProgram = "py-hellotorch";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          (python.withPackages (ps: [
            ps.torch-bin
            ps.numpy
            ps.pytest
          ]))
        ];
      };
    };
}
