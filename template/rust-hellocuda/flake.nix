{
  description = "rust + cuda hello: SAXPY via runtime NVRTC compilation";

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
            # cudarc's cuda-13020 feature matches CUDA 13.2.
            cudaPackages = final.cudaPackages_13;
          })
        ];
      };

      inherit (pkgs) lib;

      rust-hellocuda = pkgs.rustPlatform.buildRustPackage {
        pname = "rust-hellocuda";
        version = "0.1.0";
        src = ./.;
        cargoLock.lockFile = ./Cargo.lock;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postFixup = ''
          wrapProgram $out/bin/rust-hellocuda \
            --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.cudaPackages.cuda_nvrtc ]} \
            --suffix LD_LIBRARY_PATH : /run/opengl-driver/lib
        '';
        meta.mainProgram = "rust-hellocuda";
      };

      # Runs under rootless podman: a notebook cell is arbitrary code
      # execution by design, so the thing evaluating it does not get the
      # host. The evcxr kernel rebuilds a scratch crate per cell and resolves
      # `:dep cudarc = "0.19"` against crates.io, which is the main reason to
      # want it boxed in; its cargo dirs land under the project's state dir.
      #
      # cuda binds the gpu devices and the host driver into the sandbox, and
      # puts libnvrtc/libcudart on the kernel's library path -- cudarc dlopens
      # both, so it is the kernel process that needs them.
      #
      # jupyter-lsp ships no rust-analyzer spec, so the LSP features in the
      # default extension list cover python only here.
      jupyter = nornpkgs.lib.mkJupyter {
        inherit pkgs;
        name = "rust-hellocuda";
        kernels.rust = {
          displayName = "Rust (evcxr, cuda)";
          cuda = true;
        };
        port = 8891;
      };
    in
    {
      # The CUDA kernel is compiled at runtime with NVRTC, so building this
      # package needs neither a GPU nor nvcc.
      packages.${system} = {
        inherit rust-hellocuda jupyter;
        default = rust-hellocuda;
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
          # for cudarc (and anything else dlopening CUDA libs) in the shell
          env.LD_LIBRARY_PATH = "${
            lib.makeLibraryPath [
              pkgs.cudaPackages.cuda_nvrtc
              pkgs.cudaPackages.cuda_cudart
            ]
          }:/run/opengl-driver/lib";
        };

        # `nix develop .#jupyter` -- the server wrapper and podman, without
        # any of that weight in the default shell.
        jupyter = pkgs.mkShell { packages = [ jupyter ]; };
      };
    };
}
