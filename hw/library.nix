{ config, lib, pkgs, ... }:

# library: desktop, i7-12700KF + RTX 3090 + mellanox nic
let
  # board power limit for the 3090 in watts (stock 390)
  gpuPowerLimit = 280;
  # fixed duty for every nct67xx fan header, 0-255 (75 is ~29%)
  fanPwm = 75;
in
{
  imports = [ ../lib/nvidia_3090_unlock.nix ];

  boot.initrd.availableKernelModules = [ "vmd" "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "mlx5_core" ];
  boot.initrd.kernelModules = [ "kvm-intel" ];

  # nct6775: the board's NCT6798D super i/o (fans), nothing autoloads it
  boot.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" "nct6775" ];
  boot.blacklistedKernelModules = [ "nouveau" ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = true;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    open = true;

    nvidiaSettings = false;

    nvidiaPersistenced = true;
  };

  # full-rate fp16/bf16 on the 3090, set up in the initrd before nvidia
  # (stage 2, boot.kernelModules above) binds the card
  hardware.nvidia-3090-unlock.enable = true;

  # the gpu for containers
  virtualisation.docker.enableNvidia = true;

  # the power limit lives in the driver and is lost when it lets go of the
  # card; nvidia-persistenced (above) keeps it held, so set it once after
  # that and before anything puts load on the gpu
  systemd.services.nvidia-power-limit = {
    description = "Set the RTX 3090 power limit to ${toString gpuPowerLimit} W";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" "nvidia-persistenced.service" ];
    wants = [ "nvidia-persistenced.service" ];
    before = [ "gpu-timeshare.service" "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe' config.hardware.nvidia.package.bin "nvidia-smi"} -pl ${toString gpuPowerLimit}";
    };
  };

  # every nct67xx pwm channel to manual (pwmN_enable = 1) at a fixed duty.
  # hwmonN numbering is not stable across boots, so find the chip by name
  systemd.services.nct67xx-fans = {
    description = "Set nct67xx fan headers to a fixed ${toString fanPwm}/255 duty";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.gnugrep ];
    script = ''
      found=
      for d in /sys/class/hwmon/hwmon*; do
        grep -q '^nct67' "$d/name" 2>/dev/null || continue
        for p in "$d"/pwm[1-7]; do
          [ -e "$p" ] || continue
          echo 1 > "''${p}_enable"
          echo ${toString fanPwm} > "$p"
          echo "$(cat "$d/name") $(basename "$p"): manual, ${toString fanPwm}"
          found=1
        done
      done
      if [ -z "$found" ]; then
        echo "no nct67xx pwm channels under /sys/class/hwmon" >&2
        exit 1
      fi
    '';
  };
}
