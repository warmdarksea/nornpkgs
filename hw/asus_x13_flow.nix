{ config, lib, pkgs, ... }:

# ROG Flow X13 2023 (GV302XV, amd cpu + amdgpu igpu + nvidia dgpu).
# used together with (from nixos-hardware):
#   common-cpu-amd, common-cpu-amd-pstate, common-gpu-amd,
#   common-pc-laptop, common-pc-laptop-ssd
# this used to be a fork of nixos-hardware's asus/x13-flow; the delta is
# inlined here so the input can point at upstream. deliberately does NOT
# force boot.kernelPackages = linuxPackages_latest like the upstream asus
# modules do -- sys/hell pins the lts kernel for zfs.
{
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "thunderbolt" "usbhid" "usb_storage" "sd_mod" "sdhci_pci" ];
  boot.kernelModules = [ "kvm-amd" ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;

  services.xserver.videoDrivers = [ "amdgpu" ];

  # AMD has better battery life with PPD over TLP:
  # https://community.frame.work/t/responded-amd-7040-sleep-states/38101/13
  services.power-profiles-daemon.enable = lib.mkDefault true;

  # the internal keyboard chatters: a key now and then registers twice (#23).
  # filter it below the compositor, so it holds for gnome, hyprland and the
  # tty alike. the keyboard is the usb "rog n-key" device; udevmon matches ids
  # in decimal (0x0b05 asustek, 0x19b6 n-key) and skips its own uinput clone.
  # the sleep lets the key that started the service come up before the grab,
  # or the compositor never sees its release and autorepeats it.
  # drops are logged without key codes: journalctl -u interception-tools
  # to undo for a session: systemctl stop interception-tools
  services.interception-tools = {
    enable = true;
    plugins = [ pkgs.interception-debounce ];
    udevmonConfig = ''
      - JOB: "sleep 1; intercept -g $DEVNODE | debounce -t 30 | uinput -d $DEVNODE"
        DEVICE:
          VENDOR: "2821"
          PRODUCT: "6582"
          EVENTS:
            EV_KEY: [KEY_A]
    '';
  };
}
