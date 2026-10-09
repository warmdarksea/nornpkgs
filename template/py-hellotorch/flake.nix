{
  description = "python + torch hello: matrix multiply on the GPU";

  # Pinned by the committed flake.lock; `nix flake update` re-resolves it
  # through the machine's nix registry.
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

      py-hellotorch = python.pkgs.buildPythonApplication {
        pname = "py-hellotorch";
        version = "0.1.0";
        pyproject = true;
        src = ./.;
        build-system = [ python.pkgs.hatchling ];
        dependencies = [ python.pkgs.torch-bin ];
        meta.mainProgram = "py-hellotorch";
      };

      # ---- jupyter -------------------------------------------------------

      # The kernel runs out of its own env, so what a notebook can import is
      # pinned here rather than inherited from whatever started the server.
      # torch-bin needs no LD_LIBRARY_PATH: nixpkgs stamps the driver path
      # into its RUNPATH, so libcuda is found from the kernel exactly as it
      # is from the packaged binary.
      #
      # debugpy is what makes the `metadata.debugger` flag below true:
      # ipykernel does not depend on it, and without it the kernel reports no
      # debugger and jupyterlab's breakpoints quietly do nothing.
      kernelEnv = python.withPackages (ps: [
        ps.ipykernel
        ps.debugpy
        ps.torch-bin
        ps.numpy
        py-hellotorch # so a cell can `from py_hellotorch import main`
      ]);

      kernels.python3 = {
        displayName = "Python 3 (torch)";
        argv = [
          kernelEnv.interpreter
          "-m"
          "ipykernel_launcher"
          "-f"
          "{connection_file}"
        ];
        language = "python";
        # advertises the debug adapter: this is what puts the bug button in
        # jupyterlab's sidebar and lets it set breakpoints inside a cell.
        metadata.debugger = true;
        logo32 = "${kernelEnv}/${kernelEnv.sitePackages}/ipykernel/resources/logo-32x32.png";
        logo64 = "${kernelEnv}/${kernelEnv.sitePackages}/ipykernel/resources/logo-64x64.png";
      };

      # The env has ipykernel in its closure (jupyterlab depends on it), and
      # ipykernel ships a kernelspec of its own under share/jupyter/kernels.
      # JUPYTER_PATH wins for a kernel of the same name, but anything else in
      # there shows up as an extra, undeclared "Python 3 (ipykernel)" entry --
      # one whose argv is a bare `python` and which advertises a debugger this
      # env has no debugpy for. Pin the server to the kernels this flake
      # actually defines. In the env rather than the Makefile, so it holds
      # however the server was started.
      jupyterConfig = pkgs.writeTextDir "jupyter_server_config.py" ''
        c.KernelSpecManager.allowed_kernelspecs = ${builtins.toJSON (builtins.attrNames kernels)}
      '';

      # This is what pkgs.jupyter builds, with jupyterlab asked for by name.
      # notebook 7 is built on jupyterlab and so drags it in either way, but
      # pkgs.jupyter only requests notebook -- spelling it out here makes /lab
      # part of this flake's contract rather than a detail of notebook's
      # dependency list that a future bump could drop.
      jupyter =
        (python.buildEnv.override {
          extraLibs = [
            python.pkgs.notebook
            python.pkgs.jupyterlab
          ];
          makeWrapperArgs = [
            "--prefix JUPYTER_PATH : ${pkgs.jupyter-kernel.create { definitions = kernels; }}"
            "--prefix JUPYTER_CONFIG_PATH : ${jupyterConfig}"
          ];
        }).overrideAttrs
          (_: {
            meta = python.pkgs.notebook.meta // {
              mainProgram = "jupyter-notebook";
            };
          });
    in
    {
      packages.${system} = {
        inherit py-hellotorch jupyter;
        default = py-hellotorch;
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
