{ config, lib, pkgs, ... }:

# oracle cloud VM.Standard.A1.Flex (ampere altra, kvm guest).
# nixpkgs' oci-image.nix brings the platform config (loader, growpart,
# iscsi root helpers); this is the spot for shape-specific bits.
{
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" ];
}
