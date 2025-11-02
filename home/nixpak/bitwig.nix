{ pkgs, lib, mkNixPak
, bitwig-studio
, yabridge
, hostPluginsPassthru ? true  # whether to mount (ro) ~/.vst, ~/.clap, etc
, nativePlugins ? []          # list of derivations that contain audio plugins
, yabridgeEnable ? false }:

mkNixPak {
  config = { sloth, ...}: let
    # bitwig-studio-wrapped = pkgs.symlinkJoin {
    #   name = "bitwig-studio-wrapped";
    #   paths = [ pkgs.bitwig-studio5-unwrapped ];
    #   buildInputs = [ pkgs.makeWrapper ];
    #   postBuild = ''
    #     wrapProgram $out/bin/bitwig-studio \
    #     --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.findutils pkgs.gnugrep ]}"
    #   '';
    # };
    #makeHostPluginPath = format:
    #(makeSearchPath format [
    #  "$HOME/.nix-profile/lib"
    #  "/run/current-system/sw/lib"
    #  "/etc/profiles/per-user/$USER/lib"
    #]) + ":$HOME/.${format}";
    #makeStorePluginPath = format: drv: "${drv}/${format}";
    #storePluginPaths = makeSearchPath;
    #vstSearchPath = if hostPluginPassthru then 
  in rec {
    dbus.policies = {
      "org.freedesktop.systemd1" = "talk";
      "${flatpak.appId}" = "own";
      "${flatpak.appId}.*" = "own";
      "org.freedesktop.DBus" = "talk";
      "org.gtk.vfs.*" = "talk";
      "org.gtk.vfs" = "talk";
      "ca.desrt.dconf" = "talk";
      "org.freedesktop.portal.*" = "talk";
      "org.a11y.Bus" = "talk";
    };

    flatpak.appId = "com.bitwig.BitwigStudio";
    bubblewrap = {
      shareIpc = true;
      bind.rw = with sloth; [
        #[
        #  sloth.appCacheDir
        #  sloth.xdgCacheHome
        #]
        #(concat' xdgCacheHome "/fontconfig")
        #(concat' xdgCacheHome "/mesa_shader_cache")
        #(sloth.concat' sloth.runtimeDir "/at-spi/bus")
        #(sloth.concat' sloth.runtimeDir "/gvfsd")
        #(sloth.concat' sloth.runtimeDir "/dconf")
        #(sloth.concat' sloth.runtimeDir "/doc")
        #(sloth.concat' sloth.xdgCacheHome "/radv_builtin_shaders")
        (concat' homeDir "/.BitwigStudio")
        [(concat' homeDir "/Music/Bitwig Studio") (concat' homeDir "/Bitwig Studio")]
      ] ++ (if !hostPluginsPassthru then [] else [
        (concat' homeDir "/.vst")
        (concat' homeDir "/.vst3")
        (concat' homeDir "/.clap")
      ]);
      
      bind.ro = with sloth; [
        "/etc/machine-id"
        #"/etc/passwd"
        #"/etc/group"
        "/etc/os-release"
        "/etc/localtime"
        #"/run/opengl-driver"
        #(concat' xdgConfigHome "/gtk-2.0")
        #(concat' xdgConfigHome "/gtk-3.0")
        #(concat' xdgConfigHome "/gtk-4.0")
        #(concat' xdgConfigHome "/fontconfig")

        
        #(sloth.concat' sloth.xdgCacheHome "/mesa_shader_cache")
        #(sloth.concat' sloth.xdgCacheHome "/mesa_shader_cache_db")
        
        #(sloth.concat' sloth.xdgConfigHome "/dconf")

        "/userdata/software/v4x"
        "/bin/sh"
      ];
      #tmpfs = ["/tmp"];
      env = with sloth; {
        #TEST = "This is an environment variable test";
        #PATH = "${firefox}/bin";
        # XDG_DATA_DIRS = lib.makeSearchPath "share" [
        #     pkgs.adwaita-icon-theme
        #     pkgs.shared-mime-info
        #   ];
        #   XCURSOR_PATH = lib.concatStringsSep ":" [
        #     "${pkgs.adwaita-icon-theme}/share/icons"
        #     "${pkgs.adwaita-icon-theme}/share/pixmaps"
        #   ];
        #VST_PATH = concat (concat' homeDir "/.vst") [":", "${pkgs.lsp-plugins}/lib/vst"];

        # some plugins (like yabridge) don't use .../lib/vst, they just use /lib
        VST_PATH = sloth.concat ([(sloth.env "HOME") "/.vst" ":"] ++ (map (drv: "${drv}/lib/vst:${drv}/lib:") nativePlugins));
        VST3_PATH = sloth.concat ([(sloth.env "HOME") "/.vst3" ":"] ++ (map (drv: "${drv}/lib/vst3:${drv}/lib") nativePlugins));
        CLAP_PATH = sloth.concat ([(sloth.env "HOME") "/.clap" ":"] ++ (map (drv: "${drv}/lib/clap:${drv}/lib") nativePlugins));
        #VST3_PATH = "${concat' homeDir "/.vst3"}:${pkgs.lsp-plugins}/lib/vst3";
        #CLAP_PATH = "${concat' homeDir "/.clap"}:${pkgs.lsp-plugins}/lib/clap";

        NIX_PROFILES="${pkgs.yabridge}"; # needed to work around yabridge bug
      };

      extraStorePaths = nativePlugins ++ (if yabridgeEnable then with pkgs; [wineWowPackages.stable winetricks yabridge yabridgectl] else []);

      sockets = {
        wayland = true;
        pipewire = true;
        x11 = true;
      };
      
    };
    app.package = bitwig-studio;
    app.binPath = "/bin/bitwig-studio";
    etc.sslCertificates.enable = true;
    gpu.enable = true;
    gpu.provider = "bundle";
    locale.enable = true;
    fonts.enable = true;
  };
}
