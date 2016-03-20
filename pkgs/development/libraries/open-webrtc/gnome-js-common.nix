{ stdenv, fetchFromGitHub, pkgconfig
, gnome_common, intltool, libtool, glib, readline }:

stdenv.mkDerivation {

  name = "gnome-js-common-0.1.2";
  src = fetchFromGitHub {
    owner = "GNOME";
    repo = "gnome-js-common";
    rev = "66834d4003ef125b153f2573332a1fca945e7858";
    sha256 = "1ikjc5biyd5qj2f64a4yxcl52kxdacvx92rjknyvxac1i94gijjf";
  };

  propagatedBuildInputs = [
    gnome_common glib intltool libtool pkgconfig readline
  ];

  preConfigure = ''
    sh autogen.sh
  '';

}
