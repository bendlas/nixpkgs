{ stdenv, fetchgit, python, makeWrapper, pkgconfig, gcc,
  pypy, libffi, libedit, libuv, boost, zlib,
  variant ? "jit", buildWithPypy ? false }:

let
  commit-count = "1269";
  common-flags = "--thread --gcrootfinder=shadowstack --continuation";
  variants = {
    jit = { flags = "--opt=jit"; target = "target.py"; };
    jit-preload = { flags = "--opt=jit"; target = "target_preload.py"; };
    no-jit = { flags = ""; target = "target.py"; };
    no-jit-preload = { flags = ""; target = "target_preload.py"; };
  };
  pixie-src = fetchgit {
    url = "https://github.com/pixie-lang/pixie.git";
    rev = "974f85d20dc5244e5372d4a8d6ae8217571174d7";
    sha256 = "0jl32753b00qc571505m3glgjysdwp19d37rb12drx6qk8rajg4y";
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
    PYTHON = if buildWithPypy
      then "${pypy}/pypy-c/.pypy-c-wrapped"
      else "${python}/bin/python";
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
