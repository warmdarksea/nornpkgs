# Audio plugins from Nix packages into the per-user plugin folders.
#
#   audioPlugins.packages = [ nornpkgs.packages.x86_64-linux.gearmulator pkgs.lsp-plugins ];
#
# Hosts on Linux scan ~/.vst3 (per the VST3 spec), ~/.clap, ~/.lv2 and -
# by convention - ~/.vst, all of them recursively. For every package listed
# here, each plugin format it ships under lib/ is linked into the matching
# dot-folder as <dot-folder>/nix/<package name>. Only the nix/ entry is
# managed: plugins installed by hand next to it are left alone.
#
# VST3_PATH also gets one entry per listed package, for hosts configured to
# use the variable instead of the default search path. The other formats'
# variables (LV2_PATH, CLAP_PATH) *replace* the defaults in most hosts rather
# than extend them, so those are left to the dot-folders.
{ config, lib, pkgs, ... }:

let
  cfg = config.audioPlugins;

  # dot-folder in $HOME -> the lib/ subfolder packages ship it in
  formats = {
    ".vst3" = "vst3";
    ".vst" = "vst";
    ".clap" = "clap";
    ".lv2" = "lv2";
  };

  # One farm for all packages: <farm>/<format>/<package name> -> store. Built
  # by a derivation so that "which formats does this package ship" is a plain
  # directory test instead of an eval-time build of every package.
  farm = pkgs.runCommand "audio-plugin-farm" { } ''
    mkdir -p $out/vst3 $out/vst $out/clap $out/lv2
    ${lib.concatMapStrings (p: ''
      for fmt in vst3 vst clap lv2; do
        if [ -d ${p}/lib/$fmt ]; then
          ln -s ${p}/lib/$fmt "$out/$fmt/${lib.getName p}"
        fi
      done
    '') cfg.packages}
  '';
in
{
  options.audioPlugins = {
    packages = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.lsp-plugins ]";
      description = ''
        Packages whose audio plugins (anything under lib/vst3, lib/vst,
        lib/clap, lib/lv2) are linked into the user's plugin folders.
      '';
    };
  };

  config = lib.mkIf (cfg.packages != [ ]) {
    home.file = lib.mapAttrs' (dotDir: fmt: {
      name = "${dotDir}/nix";
      value.source = "${farm}/${fmt}";
    }) formats;

    # One entry per package, like the links above. A package without a
    # lib/vst3 contributes a path that does not exist, which hosts skip.
    # ~/.vst3 stays in front for plugins installed by hand: hosts that
    # honour VST3_PATH usually let it replace the default search path.
    home.sessionVariables.VST3_PATH =
      lib.concatStringsSep ":" ([ "$HOME/.vst3" ] ++ map (p: "${p}/lib/vst3") cfg.packages)
      + "\${VST3_PATH:+:$VST3_PATH}";
  };
}
