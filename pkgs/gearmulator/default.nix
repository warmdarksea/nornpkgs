# Gearmulator: low-level emulation of classic VA synths & effects as audio
# plugins (Osirus, OsTIrus, Vavra, Xenia, Nodal Red 2x, JE-8086, 88emu).
#
# Written nixpkgs-style:
#   pkgs.callPackage ./pkgs/gearmulator { }
#
# Built from our fork's 88emu-vst branch, which additionally builds the
# 88emu player (MT-32/CM/MV-30/Sound Canvas) as VST3 and VST2 plugins.
#
# Upstream's defaults are kept: every synth, VST3 + VST2 (via the bundled
# GPL FST headers - Steinberg's SDK is not fetched) + CLAP. The plugins land
# in lib/vst3, lib/vst and lib/clap. The "TUS Plugin Manager" installer is a
# network download manager and is of no use in a Nix closure, so it is off.
#
# The emulators run original firmware; ROM images are not included and are
# looked up next to the plugin or in the per-synth documents folder at
# runtime, see the upstream README.
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
  pname = "gearmulator";
  # project() version at the pinned revision; 2.2.28 is not tagged yet
  version = "2.2.28-unstable-2026-10-29";

  # Our fork, 88emu-vst branch, from the local checkout for now.
  # TODO: once the fork is pushed, switch to the GitHub copy:
  #   url = "https://github.com/<username>/gearmulator.git";
  # (same ref/rev scheme; or fetchFromGitHub with fetchSubmodules = true).
  # Upstream base: github:dsp56300/gearmulator @ 0ed1fc73 (2.2.28 pre-release).
  src = builtins.fetchGit {
    url = "file:///tmp/tmp.dXIYLCNQck/src/gearmulator";
    ref = "88emu-vst";
    rev = "0bc8e13d9128bb563933634731bc41c3d00768af";
    submodules = true;
  };

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

  cmakeFlags = [
    (lib.cmakeBool "gearmulator_BUILD_INSTALLER" false)
  ];

  # juceaide, the VST3 manifest helper and the plugin tests all run built
  # binaries, and JUCE wants somewhere to put per-user state.
  preConfigure = ''
    export HOME=$TMPDIR
  '';

  doCheck = true;
  # Unit tests plus the PluginTest label, which hosts every built plugin
  # format in the project's own pluginTester and processes audio through it.
  # No ROMs are present in the sandbox: tests that need them skip themselves,
  # except the IntegrationTest label, which downloads ROMs from the
  # maintainers' private rclone storage and cannot run here.
  checkPhase = ''
    runHook preCheck
    ctest --output-on-failure -LE IntegrationTest
    runHook postCheck
  '';

  postInstall = ''
    # The bundled 3rdparty libraries (RmlUi, lunasvg, ...) run their own
    # install rules as part of the default install; none of that is product.
    rm -rf $out/include $out/lib/cmake
    rm -f $out/lib/*.a

    # Each plugin component puts its changelog at the prefix root.
    mkdir -p $out/share/doc/${finalAttrs.pname}
    for f in "$out"/LICENSE.md "$out"/README.md "$out"/changelog*.txt; do
      if [ -e "$f" ]; then mv "$f" $out/share/doc/${finalAttrs.pname}/; fi
    done

    # The executables (test consoles and the DSPBridge server) install to the
    # prefix root; give them a bin/. The server looks for its device plugins
    # next to its own binary, so the plugins folder moves along.
    mkdir -p $out/bin
    for f in "$out"/*TestConsole "$out"/mqPerformanceTest "$out"/dsp56300EmuServer "$out"/start_*.sh; do
      if [ -e "$f" ]; then mv "$f" $out/bin/; fi
    done
    if [ -d "$out"/plugins ]; then mv "$out"/plugins $out/bin/plugins; fi
  '';

  meta = {
    description = "Emulation of classic 90s/2000s synths and sound modules as audio plugins (VST3/VST2/CLAP)";
    longDescription = ''
      Gearmulator emulates the ICs of classic musical devices - Access Virus
      A/B/C and TI, Waldorf microQ and Microwave II/XT, Clavia Nord Lead 2x,
      Roland JP-8000 and the MT-32/CM/MV-30/Sound Canvas family - and runs the
      original firmware as audio plugins. ROM images are required at runtime
      and are not included.
    '';
    homepage = "https://github.com/dsp56300/gearmulator";
    changelog = "https://github.com/dsp56300/gearmulator/blob/master/doc/changelog.txt";
    license = lib.licenses.gpl3Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
