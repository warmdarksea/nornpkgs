{ config, lib, pkgs, ... }:

# common factor of the headless machines. carries its own ssh config
# because the littledevil configurations don't import base.nix.
{
  networking.firewall.enable = lib.mkDefault true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkDefault "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted"
  ];

  # man caches take minutes to build; servers don't need them
  documentation.man.generateCaches = lib.mkForce false;
}
