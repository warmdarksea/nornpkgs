{
  imports = [ ./gpubase.nix ];
  services.xserver.videoDrivers = ["intel"];
}