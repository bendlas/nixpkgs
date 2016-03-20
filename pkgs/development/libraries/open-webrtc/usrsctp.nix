{ stdenv, fetchFromGitHub
, autoconf, automake, gettext, libtool, pkgconfig }:

stdenv.mkDerivation {

  name = "usrsctp-d00dc1";

  src = fetchFromGitHub {
    owner = "sctplab";
    repo = "usrsctp";
    rev = "d00dc1310054136ec4aa3aa71347e299483e0a4c";
    sha256 = "0yqzzvlic22z11mfhjw9y0gyj8dvy5z7qxbgsmg4cdnnz4rg3mf6";
  };

  buildInputs = [
     autoconf automake gettext libtool pkgconfig
  ];

  preConfigure = ''
    libtoolize --force
    aclocal
    autoconf
    automake --foreign --add-missing --copy
  '';

}
