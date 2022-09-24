{ stdenv, fetchFromGitHub, cmake
, libusb
}:

stdenv.mkDerivation rec {

  pname = "mouse_m908";
  version = "3.4-pre";
  src = fetchFromGitHub {
    owner = "dokutan";
    repo = pname;
    # rev = "v${version}";
    rev = "6f4e9b5c9fdfc43cd241a0a3d8f9e1736a9588bf";
    sha256 = "sha256-jat5K7P3Z5R1L5jI4pilNFU7q0xtRxwd4oXMYRW0mUU=";
  };

  nativeBuildInputs = [ cmake ];
  buildInputs = [ libusb ];

}
