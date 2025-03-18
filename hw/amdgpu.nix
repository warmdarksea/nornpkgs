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
  hardware.opengl.package = pkgs.mesa.drivers;
  hardware.opengl.package32 = pkgs.pkgsi686Linux.mesa.drivers;
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];
  hardware.opengl.extraPackages = with pkgs; [
    rocm-opencl-icd
    rocm-opencl-runtime
  ];
  environment.systemPackages = with pkgs; [ rocmPackages.clr ];
}