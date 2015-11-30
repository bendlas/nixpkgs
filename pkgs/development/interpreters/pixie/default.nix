{ stdenv, fetchgit, python, makeWrapper, pkgconfig, gcc,
  pypy, libffi, libedit, libuv, boost, zlib,
  variant ? "jit" }:

let
  commit-count = "1267";
  common-flags = "--thread --gcrootfinder=shadowstack --continuation";
  variants = {
    jit = { flags = "--opt=jit"; target = "target.py"; };
    jit-preload = { flags = "--opt=jit"; target = "target_preload.py"; };
    no-jit = { flags = ""; target = "target.py"; };
    no-jit-preload = { flags = ""; target = "target_preload.py"; };
  };
  pixie-src = fetchgit {
    url = "https://github.com/pixie-lang/pixie.git";
    rev = "244188cba48d07dc7ca71907cf7c51c4f3480b25";
    sha256 = "0vza9wb2al72r5l86c5syrflbcw9pxwdgaclnfjn6qv8xanbixx3";
  };
  libs = [ libffi libedit libuv boost.dev boost.lib zlib ];
  include-path = stdenv.lib.concatStringsSep ":"
                   (map (p: "${p}/include") libs);
  library-path = stdenv.lib.concatStringsSep ":"
                   (map (p: "${p}/lib") libs);
  bin-path = stdenv.lib.concatStringsSep ":"
               (map (p: "${p}/bin") [ gcc ]);
  build = {flags, target}: stdenv.mkDerivation rec {
    name = "pixie-${version}";
    version = "0-r${commit-count}-${variant}";
    nativeBuildInputs = libs;
    buildInputs = [ pkgconfig makeWrapper ];
    PYTHON = "${pypy}/pypy-c/.pypy-c-wrapped";
    unpackPhase = ''
      cp -R ${pixie-src} pixie-src
      mkdir pypy-src
      (cd pypy-src
       tar --strip-components=1 -xjf ${pypy.src})
      chmod -R +w pypy-src pixie-src
    '';
    patchPhase = ''
      (cd pixie-src
       patch -p1 < ${./load_paths.patch}
       libuv="${libuv}"
       libedit="${libedit}"
       libffi="${libffi}"
       boostDev="${boost.dev}"
       boostLib="${boost.lib}"
       zlib="${zlib}"
       export libuv libedit libffi boostDev boostLib zlib
       substituteAllInPlace ./pixie/ffi-infer.pxi)
    '';
    buildPhase = ''(
      PYTHONPATH="`pwd`/pypy-src:$PYTHONPATH";
      RPYTHON="`pwd`/pypy-src/rpython/bin/rpython";
      cd pixie-src
      $PYTHON $RPYTHON ${common-flags} ${target}
      export LD_LIBRARY_PATH="${library-path}:$LD_LIBRARY_PATH"
      find pixie -name "*.pxi" -exec ./pixie-vm -c {} \;
    )'';
    installPhase = ''
      mkdir -p $out/share $out/bin
      cp pixie-src/pixie-vm $out/share/pixie-vm
      cp -R pixie-src/pixie $out/share/pixie
      makeWrapper $out/share/pixie-vm $out/bin/pxi \
        --prefix LD_LIBRARY_PATH : ${library-path} \
        --prefix C_INCLUDE_PATH : ${include-path} \
        --prefix LIBRARY_PATH : ${library-path} \
        --prefix PATH : ${bin-path}
    '';
  };
in build (builtins.getAttr variant variants)
