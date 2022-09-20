{ stdenv, fetchFromGitHub, cmake
, libusb
}:

stdenv.mkDerivation rec {

  pname = "mouse_m908";
  version = "3.3";
  src = fetchFromGitHub {
    owner = "dokutan";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-jat5K7P3Z5R1L5jI4pilNFU7q0xtRxwd4oXMYRW0mUU=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ libusb ];

}
