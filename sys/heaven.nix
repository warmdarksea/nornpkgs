# windows surface pro 5
# 1. "domain join" to avoid online account
# 2. run windows update etc
# 3. install surface app from windows store
# 4. more drivers: https://www.microsoft.com/en-us/download/details.aspx?id=56278 (did i really need them?)
# 5. irm https://massgrave.dev/get | iex
# https://www.howtogeek.com/323390/how-to-fix-windows-and-linux-showing-different-times-when-dual-booting/

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

    swapDevices = [ ];

    powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    boot.loader.systemd-boot.enable = lib.mkForce false;

    boot.lanzaboote = {
      enable = true;
      # this is relative to the remote system, these files are not stored in
      # the nix store (duh)
      pkiBundle = "/etc/secureboot";
    };
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.efi.efiSysMountPoint = "/boot/EFI";

    networking.hostName = "heaven";
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

    time.timeZone = "America/New_York";

    networking.useDHCP = false;

    users.users.tenshi = {
      isNormalUser = true;
      extraGroups = ["wheel" "video"];
    };

    sound.enable = true;
    hardware.pulseaudio.enable = false;
    services.acpid.enable = true;

    programs.ssh.askPassword = "${pkgs.x11_ssh_askpass}/libexec/x11-ssh-askpass";

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
        package = pkgs.emacsPgtk;
        config = ../../emacs/config.el;
        defaultInitFile = false;

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

    system.stateVersion = "22.05";
  };
}
