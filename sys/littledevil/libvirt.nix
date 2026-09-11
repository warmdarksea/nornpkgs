{ config, pkgs, lib, ... }: {
  system.nixos.label = "libvirt";
  boot.isContainer = false;
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" ];

  boot.loader.grub = lib.mkForce {
    enable = true;
    device = "/dev/vda";
  };

  fileSystems."/" = lib.mkForce {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  # QEMU guest agent for IP reporting
  services.qemuGuest.enable = true;

  networking.interfaces.eth0 = {
    useDHCP = false;
    ipv4.addresses = [ {
      address = "0.0.0.0";
      prefixLength = 24;
    } ];
  };
  networking.defaultGateway = "0.0.0.0";
  networking.nameservers = [ "0.0.0.0" ];  # or whatever your DNS is
}
