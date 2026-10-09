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
      python = pkgs.python3;

      rust-hello = pkgs.rustPlatform.buildRustPackage {
        pname = "rust-hello";
        version = "0.1.0";
        src = ./.;
        cargoLock.lockFile = ./Cargo.lock;
        meta.mainProgram = "rust-hello";
      };

      # ---- jupyter -------------------------------------------------------

      # evcxr compiles each cell against a scratch crate, so unlike the python
      # kernels this one carries no project code: `:dep` is how a notebook
      # pulls a crate in, and that reaches for crates.io at cell-evaluation
      # time rather than resolving through this flake. The Makefile keeps the
      # resulting cargo state under $(STATE_DIR).
      #
      # evcxr speaks no DAP, so there is no `metadata.debugger` here -- the
      # flag would only put a debug button in jupyterlab that cannot work.
      # nixpkgs already wraps evcxr_jupyter with cargo/rustc/gcc on PATH,
      # which is what it shells out to for every cell. That wrapper is also
      # why the kernel logs a harmless "tried to update client, but failed:
      # Read-only file system" on startup: evcxr notices the kernel.json argv
      # is the wrapper rather than the binary it is running as and offers to
      # rewrite it, which the store rightly refuses.
      kernels.rust = {
        displayName = "Rust (evcxr)";
        argv = [
          "${pkgs.evcxr}/bin/evcxr_jupyter"
          "--control_file"
          "{connection_file}"
        ];
        language = "rust";
        logo32 = null;
        logo64 = null;
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
        inherit rust-hello jupyter;
        default = rust-hello;
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
