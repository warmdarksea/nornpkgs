import <nixpkgs/nixos> {
  system = "x86_64-linux";
  configuration = { pkgs, lib, config, ... }: {
    imports = [
      <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
      <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>
      # import your own NixOS modules here if needed
    ];
    nixpkgs.overlays = [
	    # define or import overlays here
	    #
	    (self: super: { })
	    # (import ./my-overlay.nix)
    ];

    services.qemuGuest.enable = true;

    fileSystems."/" = {
      device = "/dev/disk/by-label/REDACTED";
      fsType = "ext4";
      autoResize = true;
    };

    boot = {
      growPartition = true;
      kernelParams = [ "console=ttyS0" "boot.shell_on_fail" ];
      loader.timeout = 5;
    };

    #virtualisation = {
    #  diskSize = 8000; # MB
    #  memorySize = 2048; # MB
    #  writableStoreUseTmpfs = false;
    #};

    services.openssh.enable = true;
    services.openssh.settings.PasswordAuthentication = false;
    services.openssh.permitRootLogin = "prohibit-password";
    users.users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA redacted"
    ];

    environment.systemPackages = with pkgs;
      [ # some relevant packages here
        pkgs.ghc
      ];

    # we could alternatively hook root or a custom user
    # to some ssh key pair
    # users.extraUsers.root.password = ""; # oops
    users.mutableUsers = false;
  };
}