{ stdenv, fetchFromGitHub, cmake, llvmPackages_7, llvm-spirv, git }:
let
  version = "2019-07-30";
in

stdenv.mkDerivation rec {
  name = "opencl-clang-${version}";
  inherit version;

  src = fetchFromGitHub {
    owner = "intel";
    repo = "opencl-clang";
    ## we are on the llvm 7 branch, to support intel's compute runtime
    ## see https://github.com/intel/intel-graphics-compiler/blob/2fd7e24bfd9f76fa539fabcd2e3a065cf0adee74/documentation/build_ubuntu.md#llvmclang-version-specific-caveats
    rev = "a74228c3b6fc38834a9f85cf1eb96e1dc1359993";
    sha256 = "0213sgs0srnm38vsvcs8rw9jnwj1x8dp0wgxvg55fg9anwcq15kb";
  };
  enableParallelBuilding = true;

  buildInputs = [ cmake git ];
  propagatedBuildInputs = [ llvm-spirv llvmPackages_7.clang.cc ];

  # FIXME: llvm should have a possibility to recover original directory structure
  #   for cases like this
  patchPhase = ''
    sed -i 's#''${OPENCL_HEADERS_DIR}#${llvmPackages_7.clang.cc}/lib/clang/7.1.0/include#' cl_headers/CMakeLists.txt
  '';
  
  cmakeFlags = [ "-DLLVMSPIRV_INCLUDED_IN_LLVM=OFF"
                 "-DSPIRV_TRANSLATOR_DIR=${llvm-spirv}"
                 "-DPREFERRED_LLVM_VERSION=7.1.0" ];

  meta = with stdenv.lib; {
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = [ maintainers.bendlas ];
  };
}
