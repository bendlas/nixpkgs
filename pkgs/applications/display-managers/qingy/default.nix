{ stdenv, fetchurl, pkgconfig, lib, makeWrapper
, ncurses, openssl, xlibs, directfb, zlib
, settingsFile ? null }:

let version = "1.0.0"; in

 stdenv.mkDerivation {

  name = "qingy-${version}";
  src = fetchurl {
    url = "mirror://sourceforge/qingy/qingy-${version}.tar.bz2";
    sha256 = "1lqcfj9h4xx817p5gcqqx1mdqkd0fr38caa7ajr1ma2vilwlnjyy";
  };

  nativeBuildInputs = [ pkgconfig makeWrapper
    <nixpkgs/pkgs/build-support/setup-hooks/separate-debug-info.sh> ];

  outputs = [ "out" "debug" ];

  buildInputs = [ ncurses openssl directfb zlib ] ++ (with xlibs; [
    libX11 libXScrnSaver
  ]);

  # work around configure.in incompat with recent gcc
  configureFlags = [ "--disable-optimizations" ]
    ++ lib.optional (isNull settingsFile) [ "--sysconfdir=/etc" ];
  enableParallelBuild = true;


  installPhase = ''
    make install sysconfdir=$out/etc
    ## [FIXME] empty info file
    rm $out/share/info/qingy.info
  '' + lib.optionalString (! isNull settingsFile) ''
    rm $out/etc/qingy/settings
    ln -s ${settingsFile} $out/etc/qingy/settings
  '';

  postFixup = ''
    wrapProgram $out/bin/qingy \
      --suffix PATH : "${ncurses}/bin:${openssl}/bin:${directfb}/bin"
  '';

  inherit settingsFile;

}
