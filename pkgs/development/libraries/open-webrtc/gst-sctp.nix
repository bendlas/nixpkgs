{ stdenv, fetchFromGitHub, callPackage
, gtk_doc, autoconf, automake, gettext, libtool, pkgconfig
, gst_all_1 }: let

  usrsctp = callPackage ./usrsctp.nix { };

in stdenv.mkDerivation {

  name = "openwebrtc-gst-sctp-f40f33";
  # name = "openwebrtc-gst-sctp-0.3.0";

  src = fetchFromGitHub {
    owner = "EricssonResearch";
    repo = "openwebrtc-gst-plugins";
    # rev = "3d870ebf50727837bc38c2294f52ac0c5896a056";
    # sha256 = "13hw510cqr1vh7kdxcvq5n9n6gkjfirg9yclidc06giq1jmrr5hb";
    rev = "f40f3302007da00f0bfb82065d705b62c2ea1afd";
    sha256 = "0rz8968nlmixx2n4bm4qw56iv5pl66wy04wk0kxfgr9y674qkbh2";
  };

  buildInputs = [
     autoconf automake gettext libtool pkgconfig
  ] ++ (with gst_all_1; [
    gst-plugins-base
  ]);

  propagatedBuildInputs = [
    usrsctp
  ];

  preConfigure = ''
    sh autogen.sh
  '';

}
