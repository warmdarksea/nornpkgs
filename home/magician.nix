{lib, pkgs, nixpak, ...}: let
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
  sandboxed-bitwig = let
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
  home.packages = [sandboxed-hydrus.config.script];
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
