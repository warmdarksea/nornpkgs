# Referenced by bin/nixpkgs_maximize_cache.sh, not a NixOS module: the packages
# it checks the binary caches for at a candidate nixpkgs revision, the ones
# whose rebuild costs hours on a host or does not fit a CI runner at all. Two
# lists, because the hosts build with nixpkgs.config.cudaSupport = true and
# those derivations only ever come from cache.nixos-cuda.org, while everything
# else comes from cache.nixos.org.
#
#   nix eval --impure --json --expr 'import ./lib/bigpkgs.nix { rev = "<sha>"; }'
#   -> [ { name = "vector"; cuda = false; path = "/nix/store/...-vector-0.60.0"; } ... ]
#
# path is null when the attribute does not evaluate at that revision (renamed,
# removed, marked broken or insecure), which the script counts as a miss. Add
# an attribute when a bump turns out to build it from source.
{ rev, system ? "x86_64-linux" }:
let
  src = builtins.getFlake "github:NixOS/nixpkgs/${rev}";

  # cache.nixos.org: the big leaves of the hosts (sys/hell, home/common.nix)
  # and the base packages everything depends on.
  plainAttrs = [
    # uncached at some revision before, and a long build each
    "vector" "uhd" "gqrx" "lean4" "ghc" "haskell-language-server" "emacs-pgtk"
    # browsers, electron/qt/webkit runtimes
    "firefox" "chromium" "tor-browser" "electron" "qt6.qtwebengine"
    # the big desktop apps
    "libreoffice" "ghidra" "krita" "gimp" "blender" "obs-studio" "lsp-plugins"
    # virtualisation, containers, services
    "qemu_kvm" "incus" "podman" "docker" "libvirt" "guix"
    # toolchains and the desktop itself
    "linuxPackages.kernel" "llvmPackages.llvm" "rustc" "python3" "nodejs"
    "gnome-shell" "hyprland" "awscli2" "opentofu"
  ];

  # cache.nixos-cuda.org: the CUDA group (cuda_pkgs in home/common.nix, the
  # toolkit lib/agent.nix puts in the sandbox) and the libraries that switch
  # their build on cudaSupport.
  cudaAttrs = [
    "blender" "obs-studio"
    "cudaPackages.cudatoolkit" "cudaPackages.cudnn" "cudaPackages.nccl"
    "opencv" "onnxruntime" "python3Packages.torch" "llama-cpp" "ffmpeg-full"
  ];

  plain = import src { inherit system; config.allowUnfree = true; };
  withCuda = import src { inherit system; config = { allowUnfree = true; cudaSupport = true; }; };

  tracer = cuda: pkgs: name: let
    out = builtins.tryEval (
      let drv = pkgs.lib.getAttrFromPath (pkgs.lib.splitString "." name) pkgs;
      in builtins.unsafeDiscardStringContext drv.outPath);
  in { inherit name cuda; path = if out.success then out.value else null; };
in
  map (tracer false plain) plainAttrs ++ map (tracer true withCuda) cudaAttrs
