{ config, lib, pkgs, linuxConsoleTools, ... }:

with lib;

let
  cfg = config.hardware.powera_xb1_spectrapro;
  powera_xb1_spectrapro_pkg = stdenv.mkDerivation rec {
  pname = "ubertooth";
  version = "2020-12-R1";

  src = fetchFromGitHub {
    owner = "greatscottgadgets";
    repo = pname;
    rev = version;
    sha256 = "11r5ag2l5xn4pr7ycicm30w9c3ldn9yiqj1sqnjc79csxl2vrcfw";
  };

  sourceRoot = "source/host";

  nativeBuildInputs = [ cmake pkg-config ];
  buildInputs = [ libbtbb libpcap libusb1 bluez ];

  cmakeFlags = lib.optionals stdenv.isLinux [
    "-DINSTALL_UDEV_RULES=TRUE"
    "-DUDEV_RULES_PATH=etc/udev/rules.d"
    "-DUDEV_RULES_GROUP=${udevGroup}"
  ];

  meta = with lib; {
    description = "Open source wireless development platform suitable for Bluetooth experimentation";
    homepage = "https://github.com/greatscottgadgets/ubertooth";
    license = licenses.gpl2;
    maintainers = with maintainers; [ oxzi ];
    platforms = platforms.linux;
  };
};
in {
  options.hardware.powera_xb1_spectrapro = {
    enable = mkEnableOption "Enable udev rules to automatically calibrate/map a PowerA XB1 Spectra Pro controller.";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ powera_xb1_spectrapro_pkg linuxConsoleTools ];

    services.udev.packages = [ powera_xb1_spectraproPkg ];
  };
}
