# Packaging for Zagitta/gpu-unlock: the FP/BF16 issue-rate unlock for Ampere
# GeForce cards (GA102/GA103/GA104/GA106), which runs before the nvidia driver
# binds the card. This file is everything *except* the NixOS module itself --
# the source pin, the generated firmware, and the out-of-tree kernel module.
# The module lives in lib/nvidia_3090_unlock.nix and is exposed from the flake
# as nixosModules.nvidia_3090_unlock.
#
#   pkgs.callPackage ./hw/nvidia_3090_unlock.nix { }
#     -> { firmware; moduleFor = kernel: <drv>; src; version; }
{
  lib,
  stdenv,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  python3,
  zstd,
}:

let
  version = "1.0.0";
  nvVersion = "610.43.03";

  # Upstream checkout, pinned by commit + content hash (HEAD of main at
  # packaging time, 2026-10-24; VERSION = 1.0.0). Bumping rev means re-reviewing
  # the C: it builds and runs as a root kernel module in the initrd.
  src = fetchFromGitHub {
    owner = "Zagitta";
    repo = "gpu-unlock";
    rev = "af28cbbfd3d922a659227ecfb7369adfd924cf03";
    hash = "sha256-6FaDuPojB707ds7gkQY/g/+m4Tnz1xHZ95UjNfFxBJc=";
  };

  # Generated firmware payload. The only network-fetching inputs are the two
  # fetchurl FODs below (pinned by SHA-256); the upstream generators re-verify
  # every input byte and every output file against the hashes committed in
  # firmware/artifacts-610.43.03.json, so the five firmware files reproduce
  # bit-for-bit and the build fails closed if anything drifts.
  firmware =
    let
      # NVIDIA open kernel-module source archive (GPL-2.0 OR MIT): supplies the
      # generated BooterLoad / GspRmBoot bindata extract_boot_assets.py reads.
      nvSource = fetchurl {
        url = "https://download.nvidia.com/XFree86/NVIDIA-kernel-module-source/NVIDIA-kernel-module-source-${nvVersion}.tar.xz";
        hash = "sha256-fhGJI8eiPtw2EU1jJzpG4+BOmvmGlaQiA+esLf6fwdw=";
      };
      # CachyOS nvidia-utils package: used only to extract the exact signed
      # gsp_ga10x.bin and the NVIDIA license notice. Never installed or run.
      nvUtils = fetchurl {
        url = "https://archive.cachyos.org/archive/cachyos-v3/nvidia-utils-${nvVersion}-1-x86_64_v3.pkg.tar.zst";
        hash = "sha256-4X58ku7/oXiw/h9A6xekcJX4/Dzkp3vxFc9b1aTfhuk=";
      };
    in
    stdenvNoCC.mkDerivation {
      pname = "gpu-unlock-firmware";
      inherit version src;

      nativeBuildInputs = [
        python3
        zstd # generate_v67.py shells out to `zstd -dc`
      ];

      dontConfigure = true;

      # Mirrors the upstream Makefile `firmware` target.
      buildPhase = ''
        runHook preBuild

        mkdir -p assets.src assets
        tar -xf ${nvSource} -C assets.src
        python3 firmware/generate_v67.py "${nvUtils}" assets
        python3 firmware/extract_boot_assets.py \
          "assets.src/NVIDIA-kernel-module-source-${nvVersion}" assets

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        install -Dm644 -t "$out/lib/firmware/gpu-unlock/${nvVersion}" \
          assets/booter_load_ga102.bin \
          assets/gsp_ga10x.bin \
          assets/gsp_boot_ga102.bin \
          assets/gsp_boot_desc_ga102.bin \
          assets/v67-ga102-${nvVersion}.bin

        install -Dm644 assets/NVIDIA-LICENSE \
          "$out/share/licenses/gpu-unlock-firmware/NVIDIA-LICENSE"
        install -Dm644 firmware/NOTICE.md \
          "$out/share/licenses/gpu-unlock-firmware/NOTICE.md"

        runHook postInstall
      '';

      meta = {
        description = "Pinned NVIDIA ${nvVersion} firmware assets generated for gpu-unlock";
        homepage = "https://github.com/Zagitta/gpu-unlock";
        license = with lib.licenses; [
          unfreeRedistributableFirmware
          gpl2Only
        ];
        platforms = [ "x86_64-linux" ];
        sourceProvenance = with lib.sourceTypes; [ binaryFirmware ];
      };
    };

  # Out-of-tree build of gpu_unlock.ko against a given kernel. Built per-kernel
  # so it drops into boot.extraModulePackages cleanly.
  moduleFor =
    kernel:
    let
      # modDirVersion carries any localversion suffix; fall back to version on
      # the (rare) kernels that don't expose it.
      modDirVersion = kernel.modDirVersion or kernel.version;
    in
    stdenv.mkDerivation {
      pname = "gpu-unlock-module-${kernel.version}";
      inherit version src;

      nativeBuildInputs = kernel.moduleBuildDependencies;

      # The module's own Makefile takes KDIR and drives the kernel build system.
      buildPhase = ''
        runHook preBuild

        make -C kernel/gpu_unlock \
          KDIR="${kernel.dev}/lib/modules/${modDirVersion}/build"

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        install -Dm644 kernel/gpu_unlock/gpu_unlock.ko \
          "$out/lib/modules/${modDirVersion}/misc/gpu_unlock.ko"

        runHook postInstall
      '';

      enableParallelBuilding = true;

      meta = {
        description = "Kernel module that unlocks FP/BF16 issue rate on GA102/3/4/6 before nvidia binds";
        homepage = "https://github.com/Zagitta/gpu-unlock";
        license = lib.licenses.gpl2Only;
        platforms = [ "x86_64-linux" ];
        broken = kernel.kernelOlder "5.15";
      };
    };
in
{
  inherit src firmware moduleFor version;
}
