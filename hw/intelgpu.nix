{
  imports = [ ./gpubase.nix ];
  services.xserver.videoDrivers = ["modesetting"];
}
