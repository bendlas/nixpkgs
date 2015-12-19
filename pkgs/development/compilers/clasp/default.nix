{ stdenv, writeText, fetchurl,
  automake, autoconf, libtool, pkgconfig, gawk,
  python, llvm, clang, boost, gmp, expat, zlib, readline }:

let

  version = "0.4.0";
  local-config = writeText "clasp-local.config" ''
    export PYTHON2=${python}/bin/python
    export LLVM_CONFIG=${llvm}/bin/llvm-config
    export TARGET_OS=Linux
    export PJOBS=2
    export CLASP_VERSION=${version}
    export GIT_COMMIT=a1d32b6
    export CLANG_BIN_DIR=${clang}/bin
    export CLASP_RELEASE_CXXFLAGS=-I${clang.cc}/include
    export CLASP_RELEASE_LINKFLAGS=-L${clang.cc}/lib
    export CLASP_DEBUG_CXXFLAGS=-I${clang.cc}/include
    export CLASP_DEBUG_LINKFLAGS=-L${clang.cc}/lib
  '';

in stdenv.mkDerivation {

  name = "clasp-${version}";
#  src = fetchurl {
#    url = "https://github.com/drmeister/clasp/archive/${version}.tar.gz";
#    sha256 = "1g4wzgy3q5b27q01gxaqlvbdqj1l91r15129555azra9hqgj5m1z";
#  };
  src = /home/herwig/checkout/clasp/clasp-0.4.0-a1d32b6.tar.bz2;
  
  buildInputs = [
    automake autoconf pkgconfig libtool llvm clang boost gmp expat zlib readline
  ];

  buildFlags = "all_build";

  patchPhase = ''
    patchShebangs src/common
  '';
  
  configurePhase = ''
    cp ${local-config} local.config
  '';

}
