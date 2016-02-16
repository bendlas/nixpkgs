{ stdenv, fetchgit }:

stdenv.mkDerivation {

  name = "depot-tools";

  src = fetchgit {
    url = "https://chromium.googlesource.com/chromium/tools/depot_tools.git";
    rev = "c958da49797facf429100595bceb4c49e8c94cd3";
    sha256 = "1qba5cm4icws62b24jgxmfv2p75injagawfcvlcjhabc5lwkdmw3";
  };

  buildCommand = ''
    unpackPhase
    mkdir $out
    cp -a $sourceRoot $out/bin
    dontPatchShebangs=1
    fixupPhase
  '';

}
