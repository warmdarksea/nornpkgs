# OpenUtau DAW bridge plugin (VST3/CLAP/VST2) plus the bridge-host conformance
# harness, from our OpenUtau fork's openutau-vst branch (OpenUtau.DawPlugin/).
#
# The plugin is a loopback TCP server OpenUtau streams the project and its
# rendered vocals into (protocol: OpenUtau.Core/DawIntegration/API.md); the
# plugin plays them against the DAW transport and reports the transport back.
#
#   pkgs.callPackage ./pkgs/openutau-bridge { }
{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  alsa-lib,
  curl,
  fontconfig,
  freetype,
  libGL,
  libX11,
  libXcomposite,
  libXcursor,
  libXext,
  libXinerama,
  libXrandr,
  libXrender,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "openutau-bridge";
  version = "0.1.0-unstable-2026-10-29";

  # Our fork, openutau-vst branch, from the local checkout for now.
  # TODO: once the fork is pushed, switch to the GitHub copy:
  #   url = "https://github.com/<username>/OpenUtau.git";
  # Upstream base: github:stakira/OpenUtau @ b7c35b90.
  src = builtins.fetchGit {
    url = "https://github.com/warmdarksea/OpenUtau.git";
    ref = "openutau-vst";
    rev = "75a21a2ff719d20815a7a0eee08eacefc1275b3f";
    submodules = true;
  };

  # Only the C++ plugin subtree builds here; the C# application around it is
  # not part of this package.
  cmakeDir = "../OpenUtau.DawPlugin";

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    alsa-lib
    curl
    fontconfig
    freetype
    libGL
    libX11
    libXcomposite
    libXcursor
    libXext
    libXinerama
    libXrandr
    libXrender
  ];

  # JUCE wants somewhere to put per-user state when tools run during the build.
  preConfigure = ''
    export HOME=$TMPDIR
  '';

  doCheck = true;

  meta = {
    description = "OpenUtau DAW integration plugin (VST3/CLAP/VST2) and conformance host";
    homepage = "https://github.com/stakira/OpenUtau";
    # JUCE GPL mode + FST headers; the surrounding OpenUtau app is Apache-2.0.
    license = lib.licenses.gpl3Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "bridge-host";
  };
})
