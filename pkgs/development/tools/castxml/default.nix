{ stdenv, fetchFromGitHub
, pythonPackages
, cmake
, llvmPackages
, withMan ? true
}:
stdenv.mkDerivation rec {

  name    = "${pname}-${version}";
  pname   = "CastXML";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner  = "CastXML";
    repo   = "CastXML";
    rev    = "v${version}";
    sha256 = "1qpgr5hyb692h7l5igmq53m6a6vi4d9qp8ks893cflfx9955h3ip";
  };

  cmakeFlags = [
    "-DCLANG_RESOURCE_DIR=${llvmPackages.clang-unwrapped}"
    "-DSPHINX_MAN=${if withMan then "ON" else "OFF"}"
  ];

  buildInputs = [
    cmake
    llvmPackages.clang-unwrapped
    llvmPackages.llvm
  ] ++ stdenv.lib.optionals withMan [ pythonPackages.sphinx ];

  propagatedbuildInputs = [ llvmPackages.libclang ];

  # 97% tests passed, 96 tests failed out of 2866
  # mostly because it checks command line and nix append -isystem and all
  doCheck=false;
  checkPhase = ''
    # -E exclude 4 tests based on names
    # see https://github.com/CastXML/CastXML/issues/90
    ctest -E 'cmd.cc-(gnu|msvc)-((c-src-c)|(src-cxx))-cmd'
  '';

  meta = with stdenv.lib; {
    homepage = https://www.kitware.com;
    license = licenses.asl20;
    description = "Abstract syntax tree XML output tool";
    platforms = platforms.unix;
  };
}
