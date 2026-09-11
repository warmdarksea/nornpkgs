{ config, lib, pkgs, ... }:

# common factor of the machines with a screen and speakers.
# display managers stay per-host (gdm/gnome on some, sddm/sway on others).
{
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
  };

  hardware.bluetooth.enable = lib.mkDefault true;
}
