with import ./default.nix {}; 
gcc5.cc.override {
  langJava = false;
  langGo = false;
  langJit = false;
  inherit gtk zip unzip zlib boehmgc gettext pkgconfig perl;
  inherit (gnome) libart_lgpl;
}
