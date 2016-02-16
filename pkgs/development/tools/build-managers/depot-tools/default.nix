{ stdenv, buildFHSUserEnv, fetchgit, curl, which }:

let depot_tools = stdenv.mkDerivation rec {

  name = "depot-tools-${version}";
  version = "2017-11-09";

  src = fetchgit {
    url = "https://chromium.googlesource.com/chromium/tools/depot_tools.git";
    rev = "09baacd899ce44e9e828ec79c382a0f64c736db6";
    sha256 = "05hx8hnwmg3zm4mlhlq003p32cd9zc0bp4fqjns39rx6gjjzs3ws";
  };

  buildCommand = ''
    unpackPhase
    mkdir $out
    cp -a $sourceRoot $out/bin
    dontPatchShebangs=1
    fixupPhase
  '';

};
in
depot_tools // { shell = (buildFHSUserEnv {
  name = "depot-tools-env-${depot_tools.version}";
  targetPkgs = pkgs: (with pkgs; (
    [ git clang curl which lsb-release gn
      (python.withPackages (ppkgs:
                       with ppkgs; [ cffi_1_10 ])) ]
    ++ (with chromiumDev.browser; buildInputs ++ nativeBuildInputs)));
  runScript = "bash";
}).env; }
