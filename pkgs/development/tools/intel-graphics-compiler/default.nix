{ stdenv, fetchFromGitHub, cmake, llvmPackages_7, opencl-clang, bison, flex, python }:
let
  ## needs to fit with compute-runtime
  version = "2019-08-06";
in

stdenv.mkDerivation rec {
  name = "intel-graphics-compiler-${version}";
  inherit version;

  src = fetchFromGitHub {
    owner = "intel";
    repo = "intel-graphics-compiler";
    rev = "7c89d200bf9c5b5900d961bc6f7df5373f3d0ab6";
    sha256 = "0myradcbimpcrc2fwh82lh8a89nb7b8fbp0sbzz61196kbj3v4i0";
  };
  enableParallelBuilding = true;

  postPatch = ''
    sed -i 's#''${prefix}/##; s#''${exec_prefix}/##' IGC/AdaptorOCL/igc-opencl.pc.in
  '';

  buildInputs = [ cmake bison flex python ];
  propagatedBuildInputs = [ opencl-clang ];

  cmakeFlags = [ "-DVME_TYPES_DEFINED=FALSE" "-DIGC_PREFERRED_LLVM_VERSION=7.1.0" ];
  
  meta = with stdenv.lib; {
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = [ maintainers.bendlas ];
  };
}
