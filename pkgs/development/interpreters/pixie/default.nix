{ stdenv, makeWrapper, writeScriptBin, callPackage, libffi, libedit, libuv, boost, variant ? "jit" }:

let
  pixie-build = callPackage ./build.nix { inherit variant; };

  libs = pixie-build.nativeBuildInputs; #[ libffi libedit libuv boost ];

  C_INCLUDE_PATH = stdenv.lib.concatStringsSep ":"
                     (map (p: "${p}/include") libs);
  LIBRARY_PATH = stdenv.lib.concatStringsSep ":"
                   (map (p: "${p}/lib") libs);
  LD_LIBRARY_PATH = LIBRARY_PATH;
in stdenv.mkDerivation {
  name = "pxi-${pixie-build.version}";
  version = pixie-build.version;
  buildInputs = [ makeWrapper ];
  phases = [ "installPhase" ];
  installPhase = ''
    mkdir -p $out/bin
    makeWrapper ${pixie-build}/pixie-vm $out/bin/pxi \
      --prefix LD_LIBRARY_PATH : ${LD_LIBRARY_PATH} \
      --prefix C_INCLUDE_PATH : ${C_INCLUDE_PATH} \
      --prefix LIBRARY_PATH : ${LIBRARY_PATH}
  '';
}
/*
in writeScriptBin "pxi" ''
  #!${stdenv.shell}
  export C_INCLUDE_PATH="${C_INCLUDE_PATH}:$C_INCLUDE_PATH"
  export LIBRARY_PATH="${LIBRARY_PATH}:$LIBRARY_PATH"
  export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:$LD_LIBRARY_PATH"
  exec ${pixie-build}/pixie-vm $@
''
*/
