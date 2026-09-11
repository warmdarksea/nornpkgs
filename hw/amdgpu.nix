{config, lib, pkgs, ...}:

{
  imports = [
    ./gpubase.nix
  ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.extraModprobeConfig = ''
    options amdgpu          gpu_recovery=1
  '';
  services.xserver.videoDrivers = ["amdgpu"];
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr.icd
  ];
  environment.systemPackages = with pkgs; [ rocmPackages.clr ];
}
