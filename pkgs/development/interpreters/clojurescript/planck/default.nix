{ stdenv, fetchFromGitHub, writeScript
, clojure, curl
, webkitgtk, jdk, xxd, unzip
}:
let 
  version = "2.19.0";
  sha256 = "00x1hd7mvv83gfn54n1i8nzh0w12cmp82zi21rh80yclylgs2f6z";
  nopScript = writeScript "nop" ''
    #!${stdenv.shell}
    echo >&2 "[INFO] ignoring: $0 $@"
    exit 0
  '';
in
stdenv.mkDerivation {

  name = "planck-${version}";

  NOP_SCRIPTS = [ "get-cljsjs-long" "get-closure-compiler" "get-tcheck" ];
  patchPhase = ''
    for path in $NOP_SCRIPTS; do
      rm ./script/$path
      ln -s ${nopScript} ./script/$path
    done
    patchShebangs script
    patchShebangs planck-cljs/script
  '';

  buildPhase = ''
    ./script/build
  '';

  installPhase = ''
    ./script/install -p $out
  '';

  buildInputs = [ webkitgtk jdk xxd unzip curl clojure ];

  src = fetchFromGitHub {
    owner = "planck-repl";
    repo = "planck";
    rev = version;
    inherit sha256;
  };
  
}
