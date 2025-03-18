# windows surface pro 5
# 1. "domain join" to avoid online account
# 2. run windows update etc
# 3. install surface app from windows store
# 4. more drivers: https://www.microsoft.com/en-us/download/details.aspx?id=56278 (did i really need them?)
# 5. irm https://massgrave.dev/get | iex
# https://www.howtogeek.com/323390/how-to-fix-windows-and-linux-showing-different-times-when-dual-booting/

# nix system expr:
let overlays = [
      (self: super: import /home/satori/tmp/emacs-overlay-master/default.nix self super)
      # (self: super: {
      #   krita = (import <nixpkgs> {
      #     overlays = [(self: super: {
      #       qt5 = super.qt5.overrideScope (self: super: {
      #         qtbase = super.qtbase.overrideAttrs (o: {
      #           patches = o.patches ++ [../patches/0001-Fix-highdpi-conversion-of-QTabletEvent-coordinates-o.patch];
      #         });
      #       });
      #     })];
      #   }).krita;
      # })
      
#      (self: super: with self; {
#        gnome = super.gnome.overrideScope' (gself: gsuper: with gself; {
#          mutter = gsuper.mutter.overrideAttrs (o: {
#            src = /home/satori/src/mutter;
#          });
#        });
#      })
      ];
in import <nixpkgs/nixos> {
  system = "x86_64-linux";
  configuration = { config, lib, pkgs, modulesPath, ... }: let
    inherit overlays;
    lanzaboote = import <lanzaboote>;
    #pkgs' = import nixpkgs { inherit system; overlays = overlays; };
  in {
    imports = [
      <home-manager/nixos>
      ../profile/base.nix
      <nixos-hardware/microsoft/surface/surface-pro-5>
      lanzaboote.nixosModules.lanzaboote
      ../profile/graphical.nix
      ../session/plasma.nix
    ];

  nixpkgs.config.allowUnfree = false;
    boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usbhid" "usb_storage" "sd_mod" "pinctrl_sunrisepoint" ];
    boot.initrd.kernelModules = [ ];
    boot.kernelModules = [ "kvm-intel" "pinctrl_sunrisepoint" ];
    boot.extraModulePackages = [  ];
    boot.kernelParams = ["debug"];
    #dyndbg="file ec.c +p"

    fileSystems."/" = {
      device = "/dev/disk/by-uuid/REDACTED";
      fsType = "ext4";
    };

    boot.initrd.luks.devices."regard0".device = "/dev/disk/by-uuid/REDACTED";

    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/REDACTED";
      fsType = "ext4";
    };

    fileSystems."/boot/EFI" = {
      device = "/dev/disk/by-partuuid/REDACTED";
      fsType = "vfat";
    };

    swapDevices = [ ];

    # hardware.enableAllFirmware = true;
    powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    # high-resolution display
    # hardware.video.hidpi.enable = lib.mkDefault true;

    # Use the systemd-boot EFI boot loader.
    #boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.enable = lib.mkForce false;

    boot.lanzaboote = {
      enable = true;
      # this is relative to the remote system, these files are not stored in
      # the nix store (duh)
      #pkiBundle = "/home/satori/creds/sky/secureboot";
      pkiBundle = "/etc/secureboot";
    };
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.efi.efiSysMountPoint = "/boot/EFI";

    #boot.kernelPackages = pkgs.linuxPackages_latest;

    networking.hostName = "heaven"; # Define your hostname.
    # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    services.xserver.enable = true;
    services.xserver.displayManager.defaultSession = lib.mkForce "gnome";
    services.xserver.displayManager.gdm = {
      enable = true;
      autoLogin.enable = true;
      autoLogin.user = "tenshi";
    };
    services.xserver.desktopManager.gnome.enable = true;
    systemd.services."iptsd".serviceConfig.Restart = lib.mkForce "always";

    systemd.services."iptsd".serviceConfig.RestartSec = "5";
    
    hardware.opentabletdriver.enable = true;
    services.xserver.wacom.enable = true;
    systemd.extraConfig = ''
      DefaultTimeoutStopSec=5s
    '';

    # Set your time zone.
    time.timeZone = "America/New_York";

    # The global useDHCP flag is deprecated, therefore explicitly set to false here.
    # Per-interface useDHCP will be mandatory in the future, so this generated config
    # replicates the default behaviour.
    networking.useDHCP = false;
    #networking.interfaces.enp0s20f0u1u4.useDHCP = false;
    #networking.interfaces.wlp1s0.useDHCP = false;
    #networking.interfaces.wwp0s20f0u2.useDHCP = false;

    users.users.tenshi = {
      isNormalUser = true;
      extraGroups = ["wheel" "video"];
    };

    # Enable the X11 windowing system.
    # services.xserver.enable = true;


    

    # Configure keymap in X11
    # services.xserver.layout = "us";
    # services.xserver.xkbOptions = "eurosign:e";

    # Enable CUPS to print documents.
    # services.printing.enable = true;

    # Enable sound.
    sound.enable = true;
    hardware.pulseaudio.enable = false;
    services.acpid.enable = true;

    #programs.ssh.askPassword = lib.mkForce pkgs.seahorse;
    programs.ssh.askPassword = "${pkgs.x11_ssh_askpass}/libexec/x11-ssh-askpass";

    # Enable touchpad support (enabled default in most desktopManager).
    # services.xserver.libinput.enable = true;

    # Define a user account. Don't forget to set a password with ‘passwd’.
    # users.users.jane = {
    #   isNormalUser = true;
    #   extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    # };

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    environment.systemPackages = with pkgs; [
    #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    #   wget
    #   firefox
      pkgs.sbctl
      gcc
      libsForQt5.bismuth
      libcamera
    ];

    services.logind.extraConfig = ''
      HandlePowerKey=ignore
      KillUserProcesses=yes
    '';
    home-manager.useUserPackages = true;
    home-manager.useGlobalPkgs = true;
    home-manager.users."tenshi" = let
      # TODO: factor this out, the hard part is the overlay...
      myEmacs = (pkgs.emacsWithPackagesFromUsePackage {
        package = pkgs.emacsPgtk;  # replace with pkgs.emacsPgtk, or another version if desired.
        config = ../../emacs/config.el;
        defaultInitFile = false;

        # Optionally provide extra packages not in the configuration file.
        extraEmacsPackages = epkgs: [
          epkgs.use-package
          pkgs.chez
          pkgs.terraform-ls
        ];

        # Optionally override derivations.
        # override = epkgs: epkgs // {
        #   somePackage = epkgs.melpaPackages.somePackage.overrideAttrs(old: {
        #      # Apply fixes here
        #   });
        # };
      });
      local_infra = import ../default.nix { inherit pkgs; };
      foo = lib.debug.traceSeq {
        foobar = pkgs.gedit;
      } [];
    in {
      home.packages = with local_infra; lib.subtractLists [pkgs.chromium pkgs.element-desktop-wayland] (basepkgs ++ desktop_pkgs ++ [myEmacs pkgs.coq_8_16 pkgs.sshfs] ++ dev_pkgs ++ local_pkgs);
      home.sessionVariables = {
        "QT_QPA_PLATFORM" = "wayland-egl";
        "QT_WAYLAND_FORCE_DPI" = "physical";
        "ECORE_EVAS_ENGINE" = "wayland_egl";
        "ELM_ENGINE" = "wayland_egl";
        "SDL_VIDEODRIVER" = "wayland";
        "_JAVA_AWT_WM_NONREPARENTING" = "1";
        "MOZ_ENABLE_WAYLAND" = "1";
        "SAL_USE_VCLPLUGIN" = "gtk3";
        "PATH" ="$HOME/.local/bin:$PATH";
        "COLORTERM" = "truecolor"; # it is the year two-thousand and twenty-three
      };
      manual.manpages.enable = false;
      home.stateVersion = "22.11";
    };

    programs.bash = {
      shellInit = ''
        . "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
      '';
    };

    nixpkgs.overlays = overlays; #[
#      (self: super: import /home/satori/tmp/emacs-overlay-master/default.nix self super)
      #    # (import (builtins.fetchTarball {
      #    #   url = https://github.com/nix-community/emacs-overlay/archive/master.tar.gz;
      #    # }))
      # (self: super: {
      #   krita = super.krita.override {
      #   libsForQt5.qt5.qtbase.overrideAttrs = super.libsForQt5.qt5.qtbase.overrideAttrs (o: {
      #     patches = (o.patches or []) ++ [../patches/0001-Fix-highdpi-conversion-of-QTabletEvent-coordinates-o.patch];
      #   });
      # };
      # })
      # (self: super: {
      #   krita = (import <nixpkgs> {
      #     overlays = [(self: super: {
      #       libsForQt5.qt5.qtbase = super.libsForQt5.qt5.qtbase.overrideAttrs (o: {
      #         patches = o.patches ++ [../patches/0001-Fix-highdpi-conversion-of-QTabletEvent-coordinates-o.patch];
      #       });
      #     })];
      #   }).krita;
      # })
      # (self: super: {
      #   krita = (import <nixpkgs> {
      #     overlays = [(self: super: {
      #       qt5 = super.qt5.overrideScope (self: super: {
      #         qtbase = super.qtbase.overrideAttrs (o: {
      #           patches = o.patches ++ [../patches/0001-Fix-highdpi-conversion-of-QTabletEvent-coordinates-o.patch];
      #         });
      #       });
      #     })];
      #   }).krita;
      # })
      # (self: super: {
      #   krita = super.krita.overrideScope (self: super: {
      #     qt5 = super.qt5.overrideScope (self: super: {
      #       qtbase = super.qtbase.overrideAttrs (o: {
      #         patches = o.patches ++ [../patches/0001-Fix-highdpi-conversion-of-QTabletEvent-coordinates-o.patch];
      #       });
      #     });
      #   });
      # })
      
      # (self: super: with self; {
      #   gnome = super.gnome.overrideScope' (gself: gsuper: with gself; {
      #     mutter = gsuper.mutter.overrideAttrs (o: {
      #       src = /home/satori/src/mutter;
      #     });
      #   });
      # })
      # (self: super: {
      #   gnome = super.gnome.overrideAttrs (o: {
      #     mutter = super.mutter.overrideAttrs (o: {
      #       src = /home/satori/src/mutter;
      #     });
      #   });
      # })
      # (self: super: {
      #   gnome.mutter = super.mutter.overrideAttrs (o: {
      #     src = /home/satori/src/mutter;
      #   });
      # })
#    ];

    system.stateVersion = "22.05"; # Did you read the comment?
  };
}
