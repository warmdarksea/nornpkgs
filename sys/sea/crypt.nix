{config, lib, pkgs, ...}:

with lib;

let cfg = config.boot.crypt; in {
  options.boot.crypt = {
    enable = mkEnableOption "cryptography options";

    initramfs = mkOption {
      type = types.str;
      default = "";
      description = "Path to initramfs containing headers, keys, and symlinks to device nodes.";
    };

    header = mkOption {
      type = types.str;
      default = "";
      description = "Path to initial image LUKS header.";
    };
    image = mkOption {
      type = types.str;
      default = "";
      description = "Path to initial image file.";
    };
    image_type = mkOption {
      type = types.str;
      default = "";
      description = "Filesystem type of initial image file.";
    };


    devices = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of devices to decrypt.";
    };
    pools = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of pools to import.";
    };
    root = mkOption {
      type = types.str;
      default = "";
      description = "Root pool to mount under /mnt-root.";
    };
    root_type = mkOption {
      type = types.str;
      default = "";
      description = "Type of root pool, passed to mount -t.";
    };
  };

  config = mkIf cfg.enable {
    boot.loader.grub.extraInitrd = cfg.initramfs;
    boot.initrd.preLVMCommands = pkgs.lib.mkBefore "cat ${cfg.header} > /dev/ram0 ; cat ${cfg.image} > /dev/ram1;";
    boot.initrd.luks.devices = {
      img = {
        header = "/dev/ram0";
        device = "/dev/ram1";
        preLVM = true;
      };
    };
    boot.initrd.postDeviceCommands = ''
      mkdir /tmp/img;
      mount -t ${cfg.image_type} /dev/mapper/img /tmp/img;
      cd /tmp/img;
      for i in ${concatStringsSep " " cfg.devices}; do
        cat $i.h > /dev/ram0;
        cryptsetup luksOpen --header /dev/ram0 -d $i.k $i $i;
      done;
      cd /;
      umount /tmp/img;
      cryptsetup luksClose img;
      for i in ${concatStringsSep " " cfg.pools}; do
        zpool import -f $i;
      done;
      mount -t ${cfg.root_type} ${cfg.root} /mnt-root;
    '';
    boot.initrd.postMountCommands = "blockdev --flushbufs /dev/ram0; blockdev --flushbufs /dev/ram1;";
    boot.supportedFilesystems = [cfg.image_type cfg.root_type];
#    boot.initrd.availableKernelModules = ["loop"];
    boot.initrd.kernelModules = ["loop"];
  };


  # config = mkIf cfg.enable {
  #   # deprecated
  #   # boot.loader.grub.extraInitrd = cfg.initramfs;
  #   boot.initrd.secrets = {
  #     "/${baseNameOf cfg.header}" = "${cfg.header}";
  #     "/${baseNameOf cfg.image}" = "${cfg.image}";
  #   };
  #   boot.initrd.preLVMCommands = pkgs.lib.mkBefore "cat /${baseNameOf cfg.header} > /dev/ram0 ; cat /${baseNameOf cfg.image} > /dev/ram1;";
  #   boot.initrd.luks.devices = {
  #     img = {
  #       header = "/dev/ram0";
  #       device = "/dev/ram1";
  #       preLVM = true;
  #     };
  #   };
  #   boot.initrd.postDeviceCommands = ''
  #     mkdir /tmp/img;
  #     mount -t ${cfg.image_type} /dev/mapper/img /tmp/img;
  #     cd /tmp/img;
  #     for i in ${concatStringsSep " " cfg.devices}; do
  #       cat $i.h > /dev/ram0;
  #       cryptsetup luksOpen --header /dev/ram0 -d $i.k $i $i;
  #     done;
  #     cd /;
  #     umount /tmp/img;
  #     cryptsetup luksClose img;
  #     for i in ${concatStringsSep " " cfg.pools}; do
  #       zpool import -f $i;
  #     done;
  #     mount -t ${cfg.root_type} ${cfg.root} /mnt-root;
  #   '';
  #   boot.initrd.postMountCommands = "blockdev --flushbufs /dev/ram0; blockdev --flushbufs /dev/ram1;";
  #   boot.supportedFilesystems = [cfg.image_type cfg.root_type];
  # };
}