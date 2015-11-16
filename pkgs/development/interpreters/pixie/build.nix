{ stdenv, pypy, fetchgit, libffi, libedit, libuv, boost, pkgconfig,
  variant ? "jit" }:

let
  commit-count = "1243";
  common-flags = "--thread --gcrootfinder=shadowstack --continuation";
  variants = {
    jit = { flags = "--opt=jit"; target = "target.py"; };
    jit-preload = { flags = "--opt=jit"; target = "target_preload.py"; };
    no-jit = { flags = ""; target = "target.py"; };
    no-jit-preload = { flags = ""; target = "target_preload.py"; };
  };
  pixie-src = fetchgit {
    url = "https://github.com/pixie-lang/pixie.git";
    rev = "72f112f90a2363ed848728c6d96476a06161450f";
    sha256 = "ceb718ba1c42466920a764d516315237bb8f08e45a412b74e628f5fb28fb7603";
  };
  build = {flags, target}: stdenv.mkDerivation rec {
    name = "pixie-${version}";
    version = "0-r${commit-count}-${variant}";
    nativeBuildInputs = [ libffi libedit libuv boost ];
/*
    C_INCLUDE_PATH = stdenv.lib.concatStringsSep ":"
                       (map (p: "${p}/include") nativeBuildInputs);
    LIBRARY_PATH = stdenv.lib.concatStringsSep ":"
                     (map (p: "${p}/lib") nativeBuildInputs);
    LD_LIBRARY_PATH=LIBRARY_PATH;
*/
    buildInputs = [ pkgconfig ];
    PYTHON = "${pypy}/pypy-c/.pypy-c-wrapped";
    unpackPhase = ''
      cp -R ${pixie-src} pixie-src
      mkdir pypy-src
      (cd pypy-src
       tar --strip-components=1 -xjf ${pypy.src})
      chmod -R +w pypy-src pixie-src
    '';
    buildPhase = ''(
      PYTHONPATH="`pwd`/pypy-src:$PYTHONPATH";
      RPYTHON="`pwd`/pypy-src/rpython/bin/rpython";
      cd pixie-src
      exec $PYTHON $RPYTHON ${common-flags} ${target} >&1
    )'';
    installPhase = ''
    mkdir -p $out
    cp pixie-src/pixie-vm $out/pixie-vm
    cp -R pixie-src/pixie $out/pixie
    '';
  };
in build (builtins.getAttr variant variants)
