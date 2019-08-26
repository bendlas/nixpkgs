{ stdenv, fetchFromGitHub, cmake, llvmPackages_7 }:
let
  version = "2019-07-18";
in

stdenv.mkDerivation rec {
  name = "llvm7-spirv-${version}";
  inherit version;

  src = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SPIRV-LLVM-Translator";
    ## we are on the llvm 7 branch, to support intel's compute runtime
    ## see https://github.com/intel/intel-graphics-compiler/blob/2fd7e24bfd9f76fa539fabcd2e3a065cf0adee74/documentation/build_ubuntu.md#llvmclang-version-specific-caveats
    rev = "a296c386d666158253c144f3d3cc3d8b82cffa3f";
    sha256 = "1s9a91qnijb6160s7f9d6pscqz9xsj7jclmyx518pivs16yz1wq1";
  };
  enableParallelBuilding = true;

  buildInputs = [ cmake ];
  propagatedBuildInputs = [ llvmPackages_7.llvm ];

  meta = with stdenv.lib; {
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = [ maintainers.bendlas ];
  };
}
