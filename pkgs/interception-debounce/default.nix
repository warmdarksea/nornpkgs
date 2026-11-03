# Key-chatter filter for interception-tools (issue #23): an eager per-key
# debounce between `intercept -g` and `uinput`. See debounce.c for the
# algorithm, and hw/asus_x13_flow.nix for the udevmon job using it.
#
#   pkgs.callPackage ./pkgs/interception-debounce { }
{
  lib,
  stdenv,
  python3,
}:

stdenv.mkDerivation {
  pname = "interception-debounce";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./debounce.c ./test.py ];
  };

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Wextra -Werror -std=c11 -D_DEFAULT_SOURCE -o debounce debounce.c
    runHook postBuild
  '';

  doCheck = true;
  nativeCheckInputs = [ python3 ];
  checkPhase = ''
    runHook preCheck
    python3 test.py ./debounce
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 debounce $out/bin/debounce
    runHook postInstall
  '';

  meta = {
    description = "interception-tools plugin that filters key chatter";
    mainProgram = "debounce";
    platforms = lib.platforms.linux;
  };
}
