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
      ];
in import <nixpkgs/nixos> {
  system = "x86_64-linux";
  configuration = { config, lib, pkgs, modulesPath, ... }: let
    inherit overlays;
    lanzaboote = import <lanzaboote>;
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

    powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    # Use the systemd-boot EFI boot loader.
    boot.loader.systemd-boot.enable = lib.mkForce false;

    boot.lanzaboote = {
      enable = true;
      # this is relative to the remote system, these files are not stored in
      # the nix store (duh)
      pkiBundle = "/etc/secureboot";
    };
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.efi.efiSysMountPoint = "/boot/EFI";

    networking.hostName = "heaven"; # Define your hostname.
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

    users.users.tenshi = {
      isNormalUser = true;
      extraGroups = ["wheel" "video"];
    };

    # Enable sound.
    sound.enable = true;
    hardware.pulseaudio.enable = false;
    services.acpid.enable = true;

    programs.ssh.askPassword = "${pkgs.x11_ssh_askpass}/libexec/x11-ssh-askpass";

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    environment.systemPackages = with pkgs; [
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
      });
      local_infra = import ../default.nix { inherit pkgs; };
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

    nixpkgs.overlays = overlays;

    system.stateVersion = "22.05"; # Did you read the comment?
  };
}
