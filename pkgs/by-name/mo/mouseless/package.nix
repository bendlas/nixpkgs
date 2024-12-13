{ fetchFromGitHub, buildGoModule }:

buildGoModule rec {

  pname = "mouseless";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "jbensmann";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-iDSTV2ugvHoBuQWmMg2ILXP/Mlt7eq5B2dVaB0jwJOE=";
  };

  vendorHash = "sha256-2q7L9BVcAaT4h/vUcNjVc5nOAFnb4J3WabcEGxI+hsA=";

}
