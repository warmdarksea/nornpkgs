{ stdenv, lib, bash, linuxConsoleTools }:

stdenv.mkDerivation rec {
  name = "powera_xb1_spectra_pro";
  src = ./.;
  
  inherit linuxConsoleTools;
  installPhase = ''
  mkdir -p $out/bin
  mkdir -p $out/etc/udev/rules.d/

  substituteAll $src/calibrate.sh $out/bin/calibrate.sh
  substituteAll $src/99-powera-xb1-spectra-pro.rules $out/etc/udev/rules.d/99-powera-xb1-spectra-pro.rules

  chmod +x $out/bin/calibrate.sh
  '';
}
