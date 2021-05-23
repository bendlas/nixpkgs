# https://github.com/pavsa/hackrf-spectrum-analyzer

{ stdenv, fetchFromGitHub, cmake, pkgconfig, libusb1, fftwSinglePrec, jdk, host }:

stdenv.mkDerivation rec {
  name = "hackrf-spectrum-analyzer-${version}";
  version = "1.5";

  src = fetchFromGitHub {
    owner = "pavsa";
    repo = "hackrf-spectrum-analyzer";
    rev = version;
    sha256 = "0bggpjhs7pv02vpzylqalwbaxkgg1s3k9rxmvj7bf4b67s61mywn";
  };

  preConfigure = ''
    cd src/hackrf-sweep
  '';

  buildInputs = [
    jdk
    libusb1
    fftwSinglePrec
  ];

  meta = with stdenv.lib; {
    description = "An open source SDR platform";
    homepage = "https://greatscottgadgets.com/hackrf/";
    license = licenses.gpl2;
    platforms = platforms.all;
    maintainers = with maintainers; [ sjmackenzie ];
  };
}
