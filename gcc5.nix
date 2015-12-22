with import ./default.nix {}; 
gcc5.cc.override {
  langJava = true;
  langGo = true;
  langJit = true;
  inherit gtk zip unzip zlib boehmgc gettext pkgconfig perl;
  inherit (gnome) libart_lgpl;
}
