{ stdenv, fetchgit, emacs }:

stdenv.mkDerivation {
  name = "gn-mode-2016-04-15";
  src = fetchgit {
    url = "https://chromium.googlesource.com/chromium/src/tools/gn";
    rev = "50fa0e4bfd62838990b8b28125141460de3a495f";
    sha256 = "1gfvfs6v6pwky927fa5igi17d3f3igin7393gagxz8zgs8pg490c";
  };
  buildInputs = [ emacs ];

  buildPhase = ''
    emacs --batch -f batch-byte-compile misc/emacs/gn-mode.el
  '';

  installPhase = ''
    mkdir -p $out/share/emacs/site-lisp/
    cp misc/emacs/gn-mode.el* $out/share/emacs/site-lisp/
  '';
}
