{ stdenv, fetchgit }:

stdenv.mkDerivation {

  name = "depot-tools";

  src = fetchgit {
    url = "https://chromium.googlesource.com/chromium/tools/depot_tools.git";
    sha256 = "10560viq723zfdwcfg9gg3c4n9nl10l9qrf5l0fhxs3aknyd77j4";
  };

  buildCommand = ''
    unpackPhase
    mkdir $out
    cp -a $sourceRoot $out/bin
    dontPatchShebangs=1
    fixupPhase
  '';

}
