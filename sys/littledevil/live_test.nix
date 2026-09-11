{ config, pkgs, lib, ... }: {
  fileSystems."/data" = {
    device = config.gensokyo.disks.data or "/dev/disk/by-label/littledevil-data";
    fsType = "ext4";
  };

  services.nginx = {
    enable = true;
    virtualHosts."_" = {
      listen = [{ addr = "0.0.0.0"; port = 4000; }];
      locations."/" = {
        return = ''200 "it works\n"'';
        extraConfig = ''
            default_type text/plain;
          '';
      };
    };
  };
}
