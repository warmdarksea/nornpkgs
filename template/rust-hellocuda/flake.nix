{
  description = "rust + cuda hello: SAXPY via runtime NVRTC compilation";

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
            # cudarc's cuda-13020 feature matches CUDA 13.2.
            cudaPackages = final.cudaPackages_13;
          })
        ];
      };

      inherit (pkgs) lib;
    in
    {
      # The CUDA kernel is compiled at runtime with NVRTC, so building this
      # package needs neither a GPU nor nvcc. libcuda comes from the host
      # driver (/run/opengl-driver/lib on NixOS); libnvrtc comes from nix.
      packages.${system}.default = pkgs.rustPlatform.buildRustPackage {
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

      devShells.${system}.default = pkgs.mkShell {
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
    };
}
