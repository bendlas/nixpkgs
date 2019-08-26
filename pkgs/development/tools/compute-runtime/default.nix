{ stdenv, fetchFromGitHub, cmake
, intel-gmmlib, intel-graphics-compiler
, pkgconfig, libva, libdrm
}:
let
  version = "19.32.13826";
in

stdenv.mkDerivation rec {
  name = "compute-runtime-${version}";
  inherit version;

  src = fetchFromGitHub {
    owner = "intel";
    repo = "compute-runtime";
    rev = version;
    sha256 = "1x6y065dmv3df9bn6p4pnmzd96cvghhx55szsqjs0k1qhwmpfy7z";
  };
  enableParallelBuilding = true;
  hardeningDisable = [ "fortify" ];
  
  buildInputs = [ cmake pkgconfig libva libdrm ];
  propagatedBuildInputs = [ intel-gmmlib intel-graphics-compiler ];

  #cmakeFlags = [ "-DBUILD_TYPE=Release" "-DCMAKE_BUILD_TYPE=Release" ];
  cmakeFlags = [ "-DBUILD_TYPE=Debug" "-DCMAKE_BUILD_TYPE=Debug" ];

  makeFlags = [ "package" ];

  preBuild = ''
    mkdir -p bin
    (cd bin
     ln -s ${intel-graphics-compiler}/lib/{libigdfcl.so.1,libigc.so.1} ./
     )
  '';
  
  meta = with stdenv.lib; {
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = [ maintainers.bendlas ];
  };
}
