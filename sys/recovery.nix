{ modulesPath, pkgs, config, lib, ... }:
let
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
in
{
  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  # the image declares a GPT with three partitions. we mount the first two
  # at boot; the third is left empty and gets LUKS-formatted out-of-band
  # by provision-recovery-secrets.sh after the image is dd'd to a stick.
  fileSystems = {
    "/boot" = {
      device = "/dev/disk/by-partlabel/REDACTED";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };
    "/" = {
      device = "/dev/disk/by-partlabel/REDACTED";
      fsType = "ext4";
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.grub.enable = false;
  boot.loader.efi.canTouchEfiVariables = false;  # we're booting off a USB

  image.repart = {
    name = "gensokyo-recovery";
    partitions = {
      "10-esp" = {
        contents = {
          "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
            "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
          "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
            "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
        };
        repartConfig = {
          Type = "esp";
          Format = "vfat";
          Label = "esp";
          SizeMinBytes = "256M";
        };
      };

      "20-root" = {
        storePaths = [ config.system.build.toplevel ];
        repartConfig = {
          Type = "root";
          Format = "ext4";
          Label = "root";
          # shrink the root partition to fit the closure rather than leaving
          # gigabytes of unused empty space inside the image
          Minimize = "guess";
        };
      };

      # blank partition. no Format, no Encrypt — we want this empty so the
      # post-flash script can format it as LUKS without secrets ever passing
      # through the nix store at build time.
      "30-secrets" = {
        repartConfig = {
          Type = "linux-generic";
          Label = "gensokyo-secrets";
          SizeMinBytes = "4G";
          SizeMaxBytes = "4G";
        };
      };
    };
  };
}
