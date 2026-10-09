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

      py-hello = python.pkgs.buildPythonApplication {
        pname = "py-hello";
        version = "0.1.0";
        pyproject = true;
        src = ./.;
        build-system = [ python.pkgs.hatchling ];
        meta.mainProgram = "py-hello";
      };

      # ---- jupyter -------------------------------------------------------

      # The kernel runs out of its own env, so what a notebook can import is
      # pinned here rather than inherited from whatever started the server.
      # debugpy is what makes the `metadata.debugger` flag below true:
      # ipykernel does not depend on it, and without it the kernel reports no
      # debugger and jupyterlab's breakpoints quietly do nothing.
      kernelEnv = python.withPackages (ps: [
        ps.ipykernel
        ps.debugpy
        py-hello # so a cell can `from py_hello import main`
      ]);

      kernels.python3 = {
        displayName = "Python 3 (py-hello)";
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
        inherit py-hello jupyter;
        default = py-hello;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          (python.withPackages (ps: [ ps.pytest ]))
        ];
      };
    };
}
