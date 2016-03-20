{ stdenv, fetchgit, pkgconfig, callPackage
, webkitgtk24x, gobjectIntrospection
, gtk_doc, gettext, gnome_common, sqlite, dbus_glib
, mpfr }: let

  gnome-js-common = callPackage ./gnome-js-common.nix {
    inherit gnome_common;
  };

in stdenv.mkDerivation {

  name = "libseed-91ce78";
  src = fetchgit {
    url = "git://git.gnome.org/seed";
    rev = "91ce78cd26d026724d20ecbbd55d6bab25d96abb";
    sha256 = "196hy6bjzr7q01nqfpx4npwb8lz6l66is5wgqggsp59ns9hqljp5";
  };

  buildInputs = [
    pkgconfig gtk_doc gettext sqlite dbus_glib mpfr
  ];

  propagatedBuildInputs = [
    webkitgtk24x gobjectIntrospection gnome-js-common
  ];

  preConfigure = ''
    sh autogen.sh
  '';

}
