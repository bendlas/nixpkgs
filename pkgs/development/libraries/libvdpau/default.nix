{ stdenv, fetchurl, pkgconfig, xorg, libGL_driver }:

stdenv.mkDerivation rec {
  name = "libvdpau-${version}";
  version = "1.2";

  src = fetchurl {
    url = "https://people.freedesktop.org/~aplattner/vdpau/${name}.tar.bz2";
    sha256 = "01ps6g6p6q7j2mjm9vn44pmzq3g75mm7mdgmnhb1qkjjdwc9njba";
  };

  outputs = [ "out" "dev" ];

  nativeBuildInputs = [ pkgconfig ];
  buildInputs = with xorg; [ xorgproto libXext ];

  propagatedBuildInputs = [ xorg.libX11 ];

  configureFlags = stdenv.lib.optional stdenv.isLinux
    "--with-module-dir=${libGL_driver.driverLink}/lib/vdpau";

  NIX_LDFLAGS = if stdenv.isDarwin then "-lX11" else null;

  installFlags = [ "moduledir=$(out)/lib/vdpau" ];

  meta = with stdenv.lib; {
    homepage = https://people.freedesktop.org/~aplattner/vdpau/;
    description = "Library to use the Video Decode and Presentation API for Unix (VDPAU)";
    license = licenses.mit; # expat version
    platforms = platforms.unix;
    maintainers = [ maintainers.vcunat ];
  };
}
