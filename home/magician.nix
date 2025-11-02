{ lib, pkgs, nixpak, ... }: let

  mkNixPak = nixpak.lib.nixpak {
    inherit (pkgs) lib;
    inherit pkgs;
  };
  
  mkShellString = {
    name ? "shell",
      packages ? [],
      inputsFrom ? [],
      shellHook ? "",
      env ? {},
      pure ? true
  }: let
    lib = pkgs.lib;
    getShellInputs = drv:
      (drv.buildInputs or [])
      ++ (drv.nativeBuildInputs or [])
      ++ (drv.propagatedBuildInputs or [])
      ++ (drv.propagatedNativeBuildInputs or [])
      ++ (drv.propagatedUserEnvPkgs or []);
    expandInputsFrom = drvs: lib.unique (lib.concatMap getShellInputs drvs);
    shellPkgs = lib.unique (packages ++ expandInputsFrom inputsFrom);
    
    pkgBinPaths = builtins.map (p: "${p}/bin") shellPkgs;
    pathStr = builtins.concatStringsSep ":" (pkgBinPaths ++ ["/bin"]);
  in ''
          #!${pkgs.coreutils}/bin/env ${if pure then "-S -i" else ""} ${pkgs.bashInteractive}/bin/bash
          declare -x PATH=${pathStr}

          # begin shellHook
          ${shellHook}
          # end shellHook

          exec -a sh ${pkgs.bashInteractive}/bin/bash -i
        '';

  mkShellPath = {
    name ? "shell",
      packages ? [],
      inputsFrom ? [],
      shellHook ? "",
      env ? {},
      pure ? true
  }: let
    shellContent = mkShellString {
      inherit name packages inputsFrom shellHook env pure;
    };
  in pkgs.writeTextFile {
    name = "${name}";
    executable = true;
    text = shellContent;
  };

  # Function 3: mkShell - Creates a proper package with /nix/store/hash-name/bin/name
  mkShell = {
    name ? "shell",
      packages ? [],
      inputsFrom ? [],
      shellHook ? "",
      env ? {},
      pure ? true
  }: let
    shellFile = mkShellPath {
      inherit name packages inputsFrom shellHook env pure;
    };
  in pkgs.runCommand "${name}" {} ''
          mkdir -p $out/bin
          ln -s ${shellFile} $out/bin/${name}
        '';

  
  mkNixPakDebug = nixpak: {
    nixpakConfig ? {},
      shell ? true,
      traceOpenFiles ? false,
      debugMesa ? false,
      debugVulkan ? false
  }: let
    debugDeps = with pkgs; [nixpak.config.app.package coreutils strace findutils gnugrep xorg.xclock vulkan-tools mesa-demos which yabridge yabridgectl wineWowPackages.stable winetricks];
    
    shellDrv = mkShell {
      name = "${nixpak.config.app.package.name}-debug-shell";
      # unhelpful for debugging because nixpak passes env vars through anyway
      pure = false;
      packages = debugDeps;
      shellHook = ''
            echo in shell hook
          '';
    };
  in nixpak.extendModules {
    modules = [
      nixpakConfig
      {
        # An extra module that overrides an option:
        config.bubblewrap.extraStorePaths = pkgs.lib.mkForce (nixpak.config.bubblewrap.extraStorePaths ++ [nixpak.config.app.package pkgs.bashInteractive]);
        config.app.package = if !shell then nixpak.config.app.package else pkgs.lib.mkForce shellDrv;
        config.app.binPath = if !shell then nixpak.config.app.binPath else pkgs.lib.mkForce "/bin/${shellDrv.name}";
      }];
  };

  nixpak-desktop-wrap = pkgs.stdenv.mkDerivation {
    name = "desktop-file-wrap";

    dontUnpack = true;
    src = ./nixpak-desktop-wrap.py;
    
    nativeBuildInputs = [
      pkgs.makeWrapper
    ];
    
    installPhase = ''
            mkdir -p $out/bin $out/lib
            cp $src $out/lib/nixpak-desktop-wrap.py
            chmod +x $out/lib/nixpak-desktop-wrap.py
            
            # Create wrapper script that sets up Python environment
            makeWrapper ${pkgs.python3}/bin/python3 $out/bin/nixpak-desktop-wrap \
              --add-flags "$out/lib/nixpak-desktop-wrap.py"
          '';
  };

  # nppkg = nixpak-wrapped application
  mkNixPakApplication = nppkg: { lib, stdenv, writeTextFile, nixpak-desktop-wrap, nixpakConfig ? {} }:
    let
      nppkg' = nppkg.extendModules { modules = [ nixpakConfig ]; };
    in stdenv.mkDerivation rec {
      pname = "${nppkg'.config.app.package.name}-nixpak-wrapped";
      version = nppkg'.config.app.package.version;

      src = null;
      # Skip the unpack phase
      dontUnpack = true;
      
      # Possibly skip other unnecessary phases
      dontBuild = true;

      nativeBuildInputs = [ nixpak-desktop-wrap ];

      installPhase = let
        npdbgpkg = mkNixPakDebug nppkg' {};
        nixpakWrappedExe = "${nppkg'.config.script}/${nppkg'.config.app.binPath}";
        nixpakDebugShellExe = "${npdbgpkg.config.script}/${npdbgpkg.config.app.binPath}";
        debugDesktopFile = writeTextFile {
          name = "debugDesktopFile";
          text = ''
                  # Add a menu entry for the terminal script
                  Actions=Terminal;

                  [Desktop Action Terminal]
                  Name=Launch debug shell in terminal
                  Exec=xdg-terminal ${nixpakDebugShellExe}
                '';
        };
      in ''
              mkdir -p $out

              mkdir -p $out/bin
              ln -s "${nixpakWrappedExe}" $out/bin/

              mkdir -p $out/libexec
              ln -s "${nixpakDebugShellExe}" $out/libexec/

              mkdir -p $out/share/applications/

              for i in "${nppkg'.config.app.package}/share/applications/"*.desktop; do
                ${nixpak-desktop-wrap}/bin/nixpak-desktop-wrap "$i" "$(basename ${nppkg'.config.app.binPath})" "${nixpakWrappedExe}" > "$out/share/applications/$(basename $i)";
              done

              # append debug target to main application desktop entry
              i="$out/share/applications/${nppkg'.config.flatpak.appId}.desktop";
              if test -e "$i"; then
                cat "${debugDesktopFile}" >> "$i";
              fi

              for i in metainfo mime icons; do
                  o="${nppkg'.config.app.package}/share/$i";
                  if test -d "$o"; then
                     ln -s "$o" "$out/share/$i";
                  fi
              done
            '';
    };

  bitwig-studio6 = pkgs.bitwig-studio5-unwrapped.overrideAttrs (old: rec {
    version="6.0 Beta 5";
    src = pkgs.fetchurl {
      url = "https://www.bitwig.com/dl/Bitwig%20Studio/6.0%20Beta%205/installer_linux/bitwig-studio-6.0-beta-5.deb";
      sha256 = "sha256-v0ONhknzBrBlK99JeJ5DZuHvG19I0iaw04iM/mO7j+8=";
    };
  });

  bitwig-studio6-nixpak = (import ./nixpak/bitwig.nix) {
    inherit pkgs mkNixPak;
    inherit (pkgs) lib yabridge;

    bitwig-studio = bitwig-studio6;
    nativePlugins = with pkgs; [ lsp-plugins ];
    yabridgeEnable = true;
  };

  bitwig-studio6-nixpak-app = mkNixPakApplication bitwig-studio6-nixpak {
    inherit (pkgs) lib stdenv writeTextFile;
    inherit nixpak-desktop-wrap;
  };

  my-bitwig-studio6-nixpak-app = mkNixPakApplication bitwig-studio6-nixpak {
    inherit (pkgs) lib stdenv writeTextFile;
    inherit nixpak-desktop-wrap;

    nixpakConfig = {
      # config.bubblewrap.uid = 3280;
      # config.bubblewrap.gid = 3280;
    };
  };

  sandboxed-hydrus = let
    mkNixPak = nixpak.lib.nixpak {
      inherit (pkgs) lib;
      inherit pkgs;
    };
  in mkNixPak { 
    config = { sloth, ... }: {

      # the application to isolate
      app.package = pkgs.hydrus.overrideAttrs (self: prev: {
        buildInputs = prev.buildInputs ++ [pkgs.kdePackages.qtwayland];
      });

      # path to the executable to be wrapped
      # this is usually autodetected but
      # can be set explicitly nonetheless
      app.binPath = "bin/hydrus-client";

      # enabled by default, flip to disable
      # and to remove dependency on xdg-dbus-proxy
      dbus.enable = true;

      # same usage as --see, --talk, --own
      #dbus.policies = {
      #  "org.freedesktop.DBus" = "talk";
      #  "ca.desrt.dconf" = "talk";
      #};

      # needs to be set for Flatpak emulation
      # defaults to com.nixpak.${name}
      # where ${name} is generated from the drv name like:
      # hello -> Hello
      # my-app -> MyApp
      flatpak.appId = "org.myself.hydrus";

      gpu.enable = true;

      bubblewrap = {

        # disable all network access
        network = false;

        sockets.wayland = true;
        sockets.pipewire = true;

        #extraStorePaths = with pkgs; [ kdePackages.qtwayland ];

        # lists of paths to be mounted inside the sandbox
        # supports runtime resolution of environment variables
        # see "Sloth values" below
        bind.rw = [
          #(sloth.concat' sloth.homeDir "/Documents")
          #(sloth.env "XDG_RUNTIME_DIR")
          # a nested list represents a src -> dest mapping
          # where src != dest
          #[
          #  (sloth.concat' sloth.homeDir "/.local/state/nixpak/hello/config")
          (sloth.concat' sloth.homeDir "/.local/var/db/hydrus")
          (sloth.concat' sloth.homeDir "/.local/var/cache/hydrus")
          #]
        ];
        bind.ro = [
          #(sloth.concat' sloth.homeDir "/Downloads")
          "/etc/machine-id"
        ];
        bind.dev = [
          #"/dev/dri"
        ];
      };
    };
  };
in {
  home.packages = [
    sandboxed-hydrus.config.script
    #bitwig-sandboxed
    my-bitwig-studio6-nixpak-app
  ];
  # xdg.desktopEntries =  {
  #   hydrus = {
  #     name = "Hydrus (sandboxed)";
  #     icon = "${pkgs.hydrus}/share/icons/hicolor/scalable/apps/hydrus-client.svg";
  #     exec = "${sandboxed-hydrus.config.script}";
  #     terminal = false;
  #     categories = [ "Application" ];
  #     mimeType = [ ];
  #   };
  # };
}
